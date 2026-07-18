import Foundation

struct CodexUsageScan: Sendable {
    let isInstalled: Bool
    let files: [CodingUsageFile]
    let parentCandidates: [CodingUsageFile]
}

private struct CodexSessionFile {
    let file: CodingUsageFile
    let history: CodexFileHistory
}

private struct CodexResolvedFork: Sendable {
    let parentFile: CodingUsageFile?
    let records: [CodexUsageRecord]
}

private struct CodexUsageRecord: Sendable {
    let timestamp: Date
    let model: String?
    let usage: CodexRawUsage
}

struct CodexRawUsage: Hashable, Sendable {
    let inputTokens: UInt64
    let cachedInputTokens: UInt64
    let cacheWriteInputTokens: UInt64
    let outputTokens: UInt64

    /// Cached and cache-write tokens count subsets of `input_tokens`, so both
    /// clamp within it and `input_tokens + output_tokens` stays the total.
    init(
        inputTokens: UInt64,
        cachedInputTokens: UInt64,
        cacheWriteInputTokens: UInt64 = 0,
        outputTokens: UInt64
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = min(cachedInputTokens, inputTokens)
        self.cacheWriteInputTokens = min(
            cacheWriteInputTokens,
            inputTokens - self.cachedInputTokens
        )
        self.outputTokens = outputTokens
    }

    var isEmpty: Bool {
        inputTokens == 0 && outputTokens == 0
    }

    func subtracting(_ previous: Self?) -> Self {
        Self(
            inputTokens: inputTokens.saturatingSubtract(previous?.inputTokens ?? 0),
            cachedInputTokens: cachedInputTokens.saturatingSubtract(
                previous?.cachedInputTokens ?? 0
            ),
            cacheWriteInputTokens: cacheWriteInputTokens.saturatingSubtract(
                previous?.cacheWriteInputTokens ?? 0
            ),
            outputTokens: outputTokens.saturatingSubtract(previous?.outputTokens ?? 0)
        )
    }

    func adding(_ other: Self) -> Self {
        Self(
            inputTokens: inputTokens.saturatingAdd(other.inputTokens),
            cachedInputTokens: cachedInputTokens.saturatingAdd(other.cachedInputTokens),
            cacheWriteInputTokens: cacheWriteInputTokens.saturatingAdd(
                other.cacheWriteInputTokens
            ),
            outputTokens: outputTokens.saturatingAdd(other.outputTokens)
        )
    }
}

struct CodexUsageLoader: Sendable {
    private let fileSystem: CodingUsageFileSystem
    private let historyCache = CodingUsageFileCache<CodexFileHistory>()
    private let forkCache = CodingUsageFileCache<CodexResolvedFork>()

    init(fileSystem: CodingUsageFileSystem) {
        self.fileSystem = fileSystem
    }

    func isInstalled() -> Bool {
        fileSystem.isDirectory(homeDirectory)
    }

    func scan(scope: CodingUsageDateScope, enabled: Bool) -> CodexUsageScan {
        let isInstalled = fileSystem.isDirectory(homeDirectory)
        guard enabled && isInstalled else {
            return CodexUsageScan(isInstalled: isInstalled, files: [], parentCandidates: [])
        }
        let files = usageFiles(scope: scope)
        return CodexUsageScan(
            isInstalled: true,
            files: files.recent,
            parentCandidates: files.parentCandidates
        )
    }

    func load(_ scan: CodexUsageScan, visit: (CodingUsageEvent) -> Void) {
        let cachedHistories = historyCache.snapshot()
        let histories = concurrentMap(scan.files) { file in
            cachedHistories[file] ?? parseCodexFile(file)
        }
        let parentKeys = Set(
            histories.compactMap { $0.header?.forkParentID }
        )
        let parentFiles = scan.parentCandidates.filter { file in
            rolloutSessionIDHash(file).map(parentKeys.contains) == true
        }
        let parentHistories = concurrentMap(parentFiles) { file in
            cachedHistories[file] ?? parseCodexFile(file)
        }
        let dependencyFiles = scan.files + parentFiles
        let dependencyHistories = histories + parentHistories

        historyCache.replace(
            with: Dictionary(uniqueKeysWithValues: zip(dependencyFiles, dependencyHistories))
        )

        var filesBySession: [UInt64: CodexSessionFile] = [:]
        filesBySession.reserveCapacity(parentKeys.count)
        for (file, history) in zip(dependencyFiles, dependencyHistories) {
            guard let header = history.header else {
                continue
            }
            guard parentKeys.contains(header.idHash) else {
                continue
            }
            filesBySession[header.idHash] = CodexSessionFile(
                file: file,
                history: history
            )
        }

        let cachedForks = forkCache.snapshot()
        var resolvedForks: [CodingUsageFile: CodexResolvedFork] = [:]
        var pricing = CodexUsagePricing.Resolver()
        for (file, history) in zip(scan.files, histories) {
            let parent = history.header?.forkParentID.flatMap { filesBySession[$0] }
            let records: [CodexUsageRecord]
            if history.isFork {
                if let cached = cachedForks[file],
                    cached.parentFile == parent?.file
                {
                    records = cached.records
                } else {
                    records = history.records(inheriting: parent?.history)
                }
                resolvedForks[file] = CodexResolvedFork(
                    parentFile: parent?.file,
                    records: records
                )
            } else {
                records = history.records(inheriting: nil)
            }

            for record in records {
                guard
                    let totals = pricing.totals(model: record.model, usage: record.usage)
                else {
                    continue
                }
                visit(CodingUsageEvent(timestamp: record.timestamp, totals: totals))
            }
        }
        forkCache.replace(with: resolvedForks)
    }

    private func usageFiles(scope: CodingUsageDateScope) -> (
        recent: [CodingUsageFile], parentCandidates: [CodingUsageFile]
    ) {
        let sessions = homeDirectory.appendingPathComponent("sessions")
        let archivedSessions = homeDirectory.appendingPathComponent("archived_sessions")
        var directories: [URL] = []
        if fileSystem.isDirectory(sessions) {
            directories.append(sessions)
        }
        if fileSystem.isDirectory(archivedSessions) {
            directories.append(archivedSessions)
        }
        if directories.isEmpty {
            directories.append(homeDirectory)
        }

        var seenRelativePaths: Set<String> = []
        let files = directories.flatMap { directory in
            let pathPrefix = directory.standardizedFileURL.path + "/"
            return fileSystem.usageFiles(
                in: directory,
                modifiedSince: .distantPast
            ).filter { file in
                precondition(file.path.hasPrefix(pathPrefix))
                let relativePath = String(file.path.dropFirst(pathPrefix.count))
                return seenRelativePaths.insert(relativePath).inserted
            }
        }
        return (
            recent: files.filter { $0.modifiedAt >= scope.history.start },
            parentCandidates: files.filter { $0.modifiedAt < scope.history.start }
        )
    }

    private var homeDirectory: URL {
        fileSystem.homeDirectory.appendingPathComponent(".codex")
    }
}

private func rolloutSessionIDHash(_ file: CodingUsageFile) -> UInt64? {
    guard file.path.hasSuffix(".jsonl") else {
        return nil
    }
    let stem = file.path.dropLast(6)
    guard stem.count > 36 else {
        return nil
    }
    let separator = stem.index(stem.endIndex, offsetBy: -37)
    guard stem[separator] == "-" else {
        return nil
    }
    return codingUsageIdentityHash(stem.suffix(36).utf8)
}

private func parseCodexFile(_ file: CodingUsageFile) -> CodexFileHistory {
    var builder = CodexFileHistory.Builder()
    forEachJSONLine(in: file) { buffer in
        if let line = parseCodexLine(buffer) {
            builder.append(line)
        }
    }
    return builder.build()
}

private func nonEmptyString(_ value: String?) -> String? {
    value?.isEmpty == false ? value : nil
}

private func nonEmptyHash(_ value: JSONStringValue?) -> UInt64? {
    guard let value, value.count > 0 else {
        return nil
    }
    return value.fnv1a64
}

private func parseCodexLine(_ buffer: UnsafeRawBufferPointer) -> CodexLine? {
    guard var scanner = JSONScanner(buffer), scanner.beginObject() else {
        return nil
    }

    var fields = CodexLineFields()
    while let key = scanner.nextKey() {
        if key == "type" {
            fields.type = CodexLineType(scanner.readStringValue())
            if fields.type == .other {
                return nil
            }
        } else if key == "timestamp" {
            fields.timestamp = scanner.readStringValue()
        } else if key == "payload" {
            parseCodexPayload(&scanner, into: &fields)
        } else {
            scanner.skipValue()
        }
    }
    guard scanner.finishDocument() else {
        return nil
    }
    return fields.line
}

private func parseCodexPayload(
    _ scanner: inout JSONScanner,
    into fields: inout CodexLineFields
) {
    guard scanner.beginObject() else {
        return
    }

    while let key = scanner.nextKey() {
        if key == "type" {
            fields.isTokenCount = scanner.readStringEquals("token_count")
        } else if key == "info" {
            parseCodexInfo(&scanner, into: &fields)
        } else if key == "model" {
            fields.payloadModel = nonEmptyString(scanner.readString())
        } else if key == "id" {
            fields.sessionIDHash = nonEmptyHash(scanner.readStringValue()) ?? fields.sessionIDHash
        } else if key == "source" {
            fields.forkParentIDHash =
                parseCodexForkParent(&scanner) ?? fields.forkParentIDHash
        } else if key == "forked_from_id" {
            fields.forkParentIDHash =
                nonEmptyHash(scanner.readStringValue()) ?? fields.forkParentIDHash
        } else if key == "turn_id" {
            fields.turnIDHash = scanner.readStringValue()?.fnv1a64 ?? fields.turnIDHash
        } else {
            scanner.skipValue()
        }
    }
}

private func parseCodexForkParent(_ scanner: inout JSONScanner) -> UInt64? {
    guard scanner.beginObject() else {
        return nil
    }

    var parentIDHash: UInt64?
    while let key = scanner.nextKey() {
        if key == "subagent" {
            parentIDHash = parseCodexSubagent(&scanner) ?? parentIDHash
        } else {
            scanner.skipValue()
        }
    }
    return parentIDHash
}

private func parseCodexSubagent(_ scanner: inout JSONScanner) -> UInt64? {
    guard scanner.beginObject() else {
        return nil
    }

    var parentIDHash: UInt64?
    while let key = scanner.nextKey() {
        if key == "thread_spawn" {
            parentIDHash = parseCodexParentThreadID(&scanner) ?? parentIDHash
        } else {
            scanner.skipValue()
        }
    }
    return parentIDHash
}

private func parseCodexParentThreadID(_ scanner: inout JSONScanner) -> UInt64? {
    guard scanner.beginObject() else {
        return nil
    }

    var parentIDHash: UInt64?
    while let key = scanner.nextKey() {
        if key == "parent_thread_id" {
            parentIDHash = nonEmptyHash(scanner.readStringValue()) ?? parentIDHash
        } else {
            scanner.skipValue()
        }
    }
    return parentIDHash
}

private func parseCodexInfo(_ scanner: inout JSONScanner, into fields: inout CodexLineFields) {
    guard scanner.beginObject() else {
        return
    }

    while let key = scanner.nextKey() {
        if key == "last_token_usage" {
            if let usage = parseCodexUsage(&scanner) {
                fields.lastUsage = usage
            } else {
                fields.hasMalformedUsage = true
            }
        } else if key == "total_token_usage" {
            if let usage = parseCodexUsage(&scanner) {
                fields.totalUsage = usage
            } else {
                fields.hasMalformedUsage = true
            }
        } else {
            scanner.skipValue()
        }
    }
}

private func parseCodexUsage(_ scanner: inout JSONScanner) -> CodexRawUsage? {
    guard scanner.beginObject() else {
        return nil
    }

    var inputTokens: UInt64?
    var cachedInputTokens: UInt64?
    var cacheWriteInputTokens: UInt64 = 0
    var outputTokens: UInt64?
    var isValid = true
    while let key = scanner.nextKey() {
        if key == "input_tokens" {
            if let value = scanner.readUInt64() {
                inputTokens = value
            } else {
                isValid = false
            }
        } else if key == "cached_input_tokens" {
            if let value = scanner.readUInt64() {
                cachedInputTokens = value
            } else {
                isValid = false
            }
        } else if key == "cache_write_input_tokens" {
            // Absent before mid-2026 rollouts; serde default is zero.
            if let value = scanner.readUInt64() {
                cacheWriteInputTokens = value
            } else {
                isValid = false
            }
        } else if key == "output_tokens" {
            if let value = scanner.readUInt64() {
                outputTokens = value
            } else {
                isValid = false
            }
        } else {
            scanner.skipValue()
        }
    }
    guard isValid, let inputTokens, let cachedInputTokens, let outputTokens else {
        return nil
    }
    return CodexRawUsage(
        inputTokens: inputTokens,
        cachedInputTokens: cachedInputTokens,
        cacheWriteInputTokens: cacheWriteInputTokens,
        outputTokens: outputTokens
    )
}

private enum CodexLineType {
    case turnContext
    case eventMessage
    case sessionMeta
    case other

    init(_ value: JSONStringValue?) {
        if value?.equals("turn_context") == true {
            self = .turnContext
        } else if value?.equals("event_msg") == true {
            self = .eventMessage
        } else if value?.equals("session_meta") == true {
            self = .sessionMeta
        } else {
            self = .other
        }
    }
}

private struct CodexSessionMeta: Sendable {
    let idHash: UInt64
    let forkParentID: UInt64?
}

private enum CodexLine: Sendable {
    case sessionMeta(CodexSessionMeta)
    case turnContext(idHash: UInt64?, model: String)
    case tokenCount(CodexTokenSnapshot, at: Date)
}

private struct CodexTokenSnapshot: Hashable, Sendable {
    let lastUsage: CodexRawUsage?
    let totalUsage: CodexRawUsage?
}

private struct CodexLineFields {
    var type: CodexLineType = .other
    var timestamp: JSONStringValue?
    var isTokenCount = false
    var sessionIDHash: UInt64?
    var forkParentIDHash: UInt64?
    var turnIDHash: UInt64?
    var payloadModel: String?
    var lastUsage: CodexRawUsage?
    var totalUsage: CodexRawUsage?
    var hasMalformedUsage = false

    var line: CodexLine? {
        switch type {
        case .sessionMeta:
            guard let sessionIDHash else {
                return nil
            }
            return .sessionMeta(
                CodexSessionMeta(
                    idHash: sessionIDHash,
                    forkParentID: forkParentIDHash
                )
            )
        case .turnContext:
            guard let payloadModel else {
                return nil
            }
            return .turnContext(idHash: turnIDHash, model: payloadModel)
        case .eventMessage:
            guard isTokenCount, !hasMalformedUsage,
                let timestamp = timestamp.flatMap(LogTimestamp.parse)
            else {
                return nil
            }
            return .tokenCount(
                CodexTokenSnapshot(lastUsage: lastUsage, totalUsage: totalUsage),
                at: timestamp
            )
        case .other:
            return nil
        }
    }
}

private enum CodexReplayItem: Hashable, Sendable {
    case turnContext(idHash: UInt64)
    case tokenCount(CodexTokenSnapshot)
}

private struct CodexFileHistory: Sendable {
    struct Builder {
        private var header: CodexSessionMeta?
        private var replayItems: [CodexReplayItem] = []
        private var accountingEvents: [AccountingEvent] = []

        mutating func append(_ line: CodexLine) {
            switch line {
            case let .sessionMeta(metadata):
                if header == nil {
                    header = metadata
                }
            case let .turnContext(idHash, model):
                if let idHash {
                    replayItems.append(.turnContext(idHash: idHash))
                }
                accountingEvents.append(.turnContext(model: model))
            case let .tokenCount(snapshot, timestamp):
                replayItems.append(.tokenCount(snapshot))
                accountingEvents.append(.tokenCount(snapshot, at: timestamp))
            }
        }

        func build() -> CodexFileHistory {
            CodexFileHistory(
                header: header,
                replayItems: replayItems,
                accountingEvents: accountingEvents
            )
        }
    }

    private enum AccountingEvent: Sendable {
        case turnContext(model: String)
        case tokenCount(CodexTokenSnapshot, at: Date)
    }

    private enum Accounting: Sendable {
        case standalone(records: [CodexUsageRecord])
        case fork(events: [AccountingEvent])
    }

    let header: CodexSessionMeta?
    let replayItems: [CodexReplayItem]
    private let accounting: Accounting

    var isFork: Bool {
        if case .fork = accounting {
            return true
        }
        return false
    }

    private init(
        header: CodexSessionMeta?,
        replayItems: [CodexReplayItem],
        accountingEvents: [AccountingEvent]
    ) {
        self.header = header
        self.replayItems = replayItems
        if header?.forkParentID != nil {
            accounting = .fork(events: accountingEvents)
        } else {
            accounting = .standalone(
                records: Self.records(from: accountingEvents, ignoringInheritedTokens: 0)
            )
        }
    }

    func records(inheriting parent: CodexFileHistory?) -> [CodexUsageRecord] {
        switch accounting {
        case let .standalone(records):
            return records
        case let .fork(events):
            // Codex does not persist a replay boundary in the child rollout. Without the
            // parent sequence, inherited and child cumulative snapshots are indistinguishable.
            guard let parent else {
                return []
            }
            return Self.records(
                from: events,
                ignoringInheritedTokens: countInheritedTokens(from: parent)
            )
        }
    }

    private static func records(
        from events: [AccountingEvent],
        ignoringInheritedTokens inheritedTokenCount: Int
    ) -> [CodexUsageRecord] {
        var records: [CodexUsageRecord] = []
        var session = CodexSessionState(inheritedTokenCount: inheritedTokenCount)
        for event in events {
            switch event {
            case let .turnContext(model):
                session.onTurnContext(model: model)
            case let .tokenCount(snapshot, timestamp):
                session.onTokenCount(snapshot, at: timestamp) { records.append($0) }
            }
        }
        return records
    }

    private func countInheritedTokens(from parent: CodexFileHistory) -> Int {
        let inheritedItemCount = longestPrefix(of: replayItems, foundIn: parent.replayItems)
        return replayItems.prefix(inheritedItemCount).count {
            if case .tokenCount = $0 {
                return true
            }
            return false
        }
    }

    private func longestPrefix(
        of child: [CodexReplayItem],
        foundIn parent: [CodexReplayItem]
    ) -> Int {
        guard let first = child.first else {
            return 0
        }

        var longest = 0
        for start in parent.indices where parent[start] == first {
            var count = 0
            while count < child.count, start + count < parent.count,
                child[count] == parent[start + count]
            {
                count += 1
            }
            longest = max(longest, count)
            if longest == child.count {
                break
            }
        }
        return longest
    }
}

private struct CodexSessionState {
    private var inheritedTokenCount: Int

    private var previousTotals: CodexRawUsage?
    private var currentModel: String?

    init(inheritedTokenCount: Int) {
        self.inheritedTokenCount = inheritedTokenCount
    }

    mutating func onTurnContext(model: String) {
        currentModel = model
    }

    mutating func onTokenCount(
        _ snapshot: CodexTokenSnapshot,
        at timestamp: Date,
        emit: (CodexUsageRecord) -> Void
    ) {
        let usage = usage(from: snapshot)
        if inheritedTokenCount > 0 {
            inheritedTokenCount -= 1
            return
        }
        guard let usage, !usage.isEmpty else {
            return
        }

        emit(CodexUsageRecord(timestamp: timestamp, model: currentModel, usage: usage))
    }

    private mutating func usage(from snapshot: CodexTokenSnapshot) -> CodexRawUsage? {
        if let totalUsage = snapshot.totalUsage {
            let usage = totalUsage.subtracting(previousTotals)
            previousTotals = totalUsage
            return usage
        }
        guard let lastUsage = snapshot.lastUsage else {
            return nil
        }
        previousTotals = previousTotals?.adding(lastUsage) ?? lastUsage
        return lastUsage
    }
}
