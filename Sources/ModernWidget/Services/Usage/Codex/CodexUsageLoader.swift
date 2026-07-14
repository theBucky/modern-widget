import Foundation

struct CodexUsageSource: Sendable {
    let directory: URL
    let home: URL
    let files: [CodingUsageFile]
}

struct CodexUsageScan: Sendable {
    let isInstalled: Bool
    let sources: [CodexUsageSource]
}

private struct CodexUsageFileKey: Hashable {
    let home: String
    let relativePath: String
}

private struct CodexScopedFile {
    let home: String
    let file: CodingUsageFile
}

private struct CodexSessionKey: Hashable {
    let home: String
    let idHash: UInt64
}

private struct CodexSessionFile {
    let file: CodingUsageFile
    let history: CodexFileHistory
}

private struct CodexResolvedFork: Sendable {
    let parentFile: CodingUsageFile?
    let records: [CodexUsageRecord]
}

private struct CodexUsageRecord: Hashable, Sendable {
    let timestamp: Date
    let model: String?
    let usage: CodexRawUsage
}

private struct CodexScopedRecordKey: Hashable {
    let home: String
    let record: CodexUsageRecord
}

struct CodexRawUsage: Hashable, Sendable {
    let inputTokens: UInt64
    let cachedInputTokens: UInt64
    let outputTokens: UInt64

    init(
        inputTokens: UInt64,
        cachedInputTokens: UInt64,
        outputTokens: UInt64
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = min(cachedInputTokens, inputTokens)
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
            outputTokens: outputTokens.saturatingSubtract(previous?.outputTokens ?? 0)
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
        !homeDirectories().isEmpty
    }

    func scan(scope: CodingUsageDateScope, enabled: Bool) -> CodexUsageScan {
        let homes = homeDirectories()
        let sources = enabled ? usageSources(homes: homes, scope: scope) : []
        return CodexUsageScan(isInstalled: !homes.isEmpty, sources: sources)
    }

    func load(_ scan: CodexUsageScan, visit: (CodingUsageEvent) -> Void) {
        let files = scopedFiles(in: scan)
        let cachedHistories = historyCache.snapshot()
        let histories = concurrentMap(files) { scopedFile in
            cachedHistories[scopedFile.file] ?? parseCodexFile(scopedFile.file)
        }

        var historiesByFile: [CodingUsageFile: CodexFileHistory] = [:]
        historiesByFile.reserveCapacity(files.count)
        for (scopedFile, history) in zip(files, histories) {
            historiesByFile[scopedFile.file] = history
        }
        historyCache.replace(with: historiesByFile)

        let parentKeys = Set(
            zip(files, histories).compactMap { scopedFile, history in
                history.header?.forkParentID.map {
                    CodexSessionKey(home: scopedFile.home, idHash: $0)
                }
            }
        )
        var filesBySession: [CodexSessionKey: CodexSessionFile] = [:]
        filesBySession.reserveCapacity(parentKeys.count)
        for (scopedFile, history) in zip(files, histories) {
            guard let header = history.header else {
                continue
            }
            let key = CodexSessionKey(home: scopedFile.home, idHash: header.idHash)
            guard parentKeys.contains(key) else {
                continue
            }
            filesBySession[key] = CodexSessionFile(
                file: scopedFile.file,
                history: history
            )
        }

        let cachedForks = forkCache.snapshot()
        var resolvedForks: [CodingUsageFile: CodexResolvedFork] = [:]
        var seenRecords: Set<CodexScopedRecordKey> = []
        var pricing = CodexUsageCostResolver()
        for (scopedFile, history) in zip(files, histories) {
            let parent = history.header?.forkParentID.flatMap {
                filesBySession[CodexSessionKey(home: scopedFile.home, idHash: $0)]
            }
            let records: [CodexUsageRecord]
            if history.isFork {
                if let cached = cachedForks[scopedFile.file],
                    cached.parentFile == parent?.file
                {
                    records = cached.records
                } else {
                    records = history.records(inheriting: parent?.history)
                }
                resolvedForks[scopedFile.file] = CodexResolvedFork(
                    parentFile: parent?.file,
                    records: records
                )
            } else {
                records = history.records(inheriting: nil)
            }

            for record in records {
                guard
                    seenRecords.insert(
                        CodexScopedRecordKey(home: scopedFile.home, record: record)
                    ).inserted,
                    let totals = pricing.totals(model: record.model, usage: record.usage)
                else {
                    continue
                }
                visit(CodingUsageEvent(timestamp: record.timestamp, totals: totals))
            }
        }
        forkCache.replace(with: resolvedForks)
    }

    private func scopedFiles(in scan: CodexUsageScan) -> [CodexScopedFile] {
        var seen: Set<CodexUsageFileKey> = []
        return scan.sources.flatMap { source in
            source.files.compactMap { file in
                let home = source.home.path
                let key = CodexUsageFileKey(
                    home: home,
                    relativePath: fileSystem.relativePath(file.url, from: source.directory)
                )
                guard seen.insert(key).inserted else {
                    return nil
                }
                return CodexScopedFile(home: home, file: file)
            }
        }
    }

    private func usageSources(
        homes: [URL],
        scope: CodingUsageDateScope
    ) -> [CodexUsageSource] {
        homes.flatMap { home in
            let sessions = home.appendingPathComponent("sessions")
            let archivedSessions = home.appendingPathComponent("archived_sessions")
            var directories: [URL] = []
            if fileSystem.isDirectory(sessions) {
                directories.append(sessions)
            }
            if fileSystem.isDirectory(archivedSessions) {
                directories.append(archivedSessions)
            }
            if directories.isEmpty {
                directories.append(home)
            }

            return directories.map { directory in
                CodexUsageSource(
                    directory: directory,
                    home: home,
                    files: fileSystem.usageFiles(
                        in: [directory],
                        modifiedSince: scope.history.start
                    )
                )
            }
        }
    }

    private func homeDirectories() -> [URL] {
        fileSystem.configuredDirectories(environmentKey: "CODEX_HOME") {
            [fileSystem.homeDirectory.appendingPathComponent(".codex")]
        }
        .filter(fileSystem.isDirectory)
    }
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
            switch parseCodexPayload(&scanner, into: &fields) {
            case .relevant:
                break
            case .irrelevant:
                return nil
            case .complete:
                return fields.line
            }
        } else {
            scanner.skipValue()
        }
    }
    return fields.line
}

private enum CodexPayloadScanResult {
    case relevant
    case irrelevant
    case complete
}

private func parseCodexPayload(
    _ scanner: inout JSONScanner,
    into fields: inout CodexLineFields
) -> CodexPayloadScanResult {
    guard scanner.beginObject() else {
        return .relevant
    }

    while let key = scanner.nextKey() {
        if key == "type" {
            fields.isTokenCount = scanner.readStringEquals("token_count")
            if !fields.isTokenCount, fields.type == .eventMessage {
                return .irrelevant
            }
        } else if key == "info" {
            parseCodexInfo(&scanner, into: &fields)
        } else if key == "model" {
            fields.payloadModel = nonEmptyString(scanner.readString())
            if fields.type == .turnContext,
                fields.turnIDHash != nil, fields.payloadModel != nil
            {
                return .complete
            }
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
            if fields.type == .turnContext, fields.payloadModel != nil {
                return .complete
            }
        } else {
            scanner.skipValue()
        }

        if fields.type == .sessionMeta,
            fields.sessionIDHash != nil, fields.forkParentIDHash != nil
        {
            return .complete
        }
    }
    return .relevant
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
            fields.lastUsage = parseCodexUsage(&scanner)
        } else if key == "total_token_usage" {
            fields.totalUsage = parseCodexUsage(&scanner)
        } else if key == "model" {
            fields.infoModel = nonEmptyString(scanner.readString())
        } else {
            scanner.skipValue()
        }
    }
}

private func parseCodexUsage(_ scanner: inout JSONScanner) -> CodexRawUsage? {
    guard scanner.beginObject() else {
        return nil
    }

    var inputTokens: UInt64 = 0
    var cachedInputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    while let key = scanner.nextKey() {
        if key == "input_tokens" {
            inputTokens = scanner.readUInt64() ?? 0
        } else if key == "cached_input_tokens" {
            cachedInputTokens = scanner.readUInt64() ?? 0
        } else if key == "output_tokens" {
            outputTokens = scanner.readUInt64() ?? 0
        } else {
            scanner.skipValue()
        }
    }
    return CodexRawUsage(
        inputTokens: inputTokens,
        cachedInputTokens: cachedInputTokens,
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
    let model: String?
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
    var infoModel: String?

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
            guard isTokenCount, let timestamp = timestamp.flatMap(LogTimestamp.parse) else {
                return nil
            }
            return .tokenCount(
                CodexTokenSnapshot(
                    model: payloadModel ?? infoModel,
                    lastUsage: lastUsage,
                    totalUsage: totalUsage
                ),
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
        if inheritedTokenCount > 0 {
            inheritedTokenCount -= 1
            updatePreviousTotals(from: snapshot)
            return
        }
        emitRecord(from: snapshot, at: timestamp, emit: emit)
    }

    private mutating func emitRecord(
        from snapshot: CodexTokenSnapshot,
        at timestamp: Date,
        emit: (CodexUsageRecord) -> Void
    ) {
        let usage = snapshot.totalUsage?.subtracting(previousTotals) ?? snapshot.lastUsage
        updatePreviousTotals(from: snapshot)
        guard let usage, !usage.isEmpty else {
            return
        }

        if let model = snapshot.model {
            currentModel = model
        }
        emit(CodexUsageRecord(timestamp: timestamp, model: currentModel, usage: usage))
    }

    private mutating func updatePreviousTotals(from snapshot: CodexTokenSnapshot) {
        if let totalUsage = snapshot.totalUsage {
            previousTotals = totalUsage
        }
    }
}
