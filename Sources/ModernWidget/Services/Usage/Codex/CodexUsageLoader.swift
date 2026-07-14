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
    private let cache = CodingUsageFileCache<CodexUsageRecord>()

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
        var seenFiles: Set<CodexUsageFileKey> = []
        var seenRecords: Set<CodexScopedRecordKey> = []
        var pricing = CodexUsageCostResolver()
        let cachedRecords = cache.snapshot()
        var recordsByFile: [CodingUsageFile: [CodexUsageRecord]] = [:]
        recordsByFile.reserveCapacity(scan.sources.lazy.map(\.files.count).reduce(0, +))

        let sourceCountByHome = Dictionary(
            grouping: scan.sources.filter { !$0.files.isEmpty },
            by: { $0.home.path }
        )
        .mapValues(\.count)

        for source in scan.sources where !source.files.isEmpty {
            let home = source.home.path
            let files: [CodingUsageFile]
            if sourceCountByHome[home, default: 0] > 1 {
                files = source.files.filter { file in
                    seenFiles.insert(
                        CodexUsageFileKey(
                            home: home,
                            relativePath: fileSystem.relativePath(file.url, from: source.directory)
                        )
                    ).inserted
                }
            } else {
                files = source.files
            }

            let recordsForFiles = concurrentMap(files) { file in
                if let cached = cachedRecords[file] {
                    return cached
                }

                var records: [CodexUsageRecord] = []
                parseCodexFile(file) { records.append($0) }
                return records
            }

            for (file, records) in zip(files, recordsForFiles) {
                recordsByFile[file] = records
                for record in records {
                    guard
                        seenRecords.insert(
                            CodexScopedRecordKey(home: home, record: record)
                        ).inserted
                    else {
                        continue
                    }
                    guard
                        let totals = pricing.totals(
                            model: record.model,
                            usage: record.usage
                        )
                    else {
                        continue
                    }
                    visit(CodingUsageEvent(timestamp: record.timestamp, totals: totals))
                }
            }
        }

        cache.replace(with: recordsByFile)
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

private func parseCodexFile(
    _ file: CodingUsageFile,
    visit: (CodexUsageRecord) -> Void
) {
    var session = CodexSessionState()
    forEachJSONLine(in: file) { buffer in
        guard let line = parseCodexLine(buffer) else {
            return
        }
        switch line {
        case let .sessionMeta(metadata, timestamp):
            session.onSessionMeta(metadata, at: timestamp)
        case let .turnContext(model, timestamp):
            session.onTurnContext(model: model, at: timestamp)
        case let .tokenCount(snapshot, timestamp):
            session.onTokenCount(snapshot, at: timestamp, emit: visit)
        }
    }
}

private func nonEmptyString(_ value: String?) -> String? {
    value?.isEmpty == false ? value : nil
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
            if fields.type == .turnContext, fields.timestamp != nil,
                fields.payloadModel != nil
            {
                return .complete
            }
        } else if key == "id" {
            fields.sessionID = nonEmptyString(scanner.readString()) ?? fields.sessionID
        } else if key == "source" {
            fields.forkParentID = parseCodexForkParent(&scanner) ?? fields.forkParentID
        } else if key == "forked_from_id" {
            fields.forkParentID = nonEmptyString(scanner.readString()) ?? fields.forkParentID
        } else {
            scanner.skipValue()
        }

        if fields.type == .sessionMeta, fields.timestamp != nil,
            fields.sessionID != nil, fields.forkParentID != nil
        {
            return .complete
        }
    }
    return .relevant
}

private func parseCodexForkParent(_ scanner: inout JSONScanner) -> String? {
    guard scanner.beginObject() else {
        return nil
    }

    var parentID: String?
    while let key = scanner.nextKey() {
        if key == "subagent" {
            parentID = parseCodexSubagent(&scanner) ?? parentID
        } else {
            scanner.skipValue()
        }
    }
    return parentID
}

private func parseCodexSubagent(_ scanner: inout JSONScanner) -> String? {
    guard scanner.beginObject() else {
        return nil
    }

    var parentID: String?
    while let key = scanner.nextKey() {
        if key == "thread_spawn" {
            parentID = parseCodexParentThreadID(&scanner) ?? parentID
        } else {
            scanner.skipValue()
        }
    }
    return parentID
}

private func parseCodexParentThreadID(_ scanner: inout JSONScanner) -> String? {
    guard scanner.beginObject() else {
        return nil
    }

    var parentID: String?
    while let key = scanner.nextKey() {
        if key == "parent_thread_id" {
            parentID = nonEmptyString(scanner.readString()) ?? parentID
        } else {
            scanner.skipValue()
        }
    }
    return parentID
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

private struct CodexSessionMeta {
    let id: String?
    let forkParentID: String?

    init?(id: String?, forkParentID: String?) {
        guard id != nil || forkParentID != nil else {
            return nil
        }
        self.id = id
        self.forkParentID = forkParentID
    }
}

private enum CodexLine {
    case sessionMeta(CodexSessionMeta, at: Date)
    case turnContext(model: String, at: Date)
    case tokenCount(CodexTokenSnapshot, at: Date)
}

private struct CodexTokenSnapshot {
    let model: String?
    let lastUsage: CodexRawUsage?
    let totalUsage: CodexRawUsage?
}

private struct CodexLineFields {
    var type: CodexLineType = .other
    var timestamp: JSONStringValue?
    var isTokenCount = false
    var sessionID: String?
    var forkParentID: String?
    var payloadModel: String?
    var lastUsage: CodexRawUsage?
    var totalUsage: CodexRawUsage?
    var infoModel: String?

    var line: CodexLine? {
        guard let timestamp = timestamp.flatMap(LogTimestamp.parse) else {
            return nil
        }
        switch type {
        case .sessionMeta:
            guard let metadata = CodexSessionMeta(id: sessionID, forkParentID: forkParentID) else {
                return nil
            }
            return .sessionMeta(metadata, at: timestamp)
        case .turnContext:
            guard let payloadModel else {
                return nil
            }
            return .turnContext(model: payloadModel, at: timestamp)
        case .eventMessage:
            guard isTokenCount else {
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

private struct CodexSessionState {
    private struct Replay {
        enum Phase {
            case awaitingParent(id: String)
            case replaying
        }

        let startedAt: Date
        let phase: Phase
    }

    private static let replayWindowDuration: TimeInterval = 1

    private var previousTotals: CodexRawUsage?
    private var currentModel: String?
    private var hasSessionHeader = false
    private var replay: Replay?

    mutating func onSessionMeta(_ metadata: CodexSessionMeta, at timestamp: Date) {
        expireReplay(at: timestamp)
        if !hasSessionHeader {
            hasSessionHeader = true
            guard let parentID = metadata.forkParentID else {
                return
            }
            replay = Replay(startedAt: timestamp, phase: .awaitingParent(id: parentID))
            return
        }

        guard let id = metadata.id, let replay,
            case let .awaitingParent(parentID) = replay.phase,
            id == parentID
        else {
            return
        }
        self.replay = Replay(startedAt: replay.startedAt, phase: .replaying)
    }

    mutating func onTurnContext(model: String, at timestamp: Date) {
        expireReplay(at: timestamp)
        currentModel = model
    }

    mutating func onTokenCount(
        _ snapshot: CodexTokenSnapshot,
        at timestamp: Date,
        emit: (CodexUsageRecord) -> Void
    ) {
        expireReplay(at: timestamp)
        if let replay, case .replaying = replay.phase {
            updatePreviousTotals(from: snapshot)
            return
        }
        replay = nil
        emitRecord(from: snapshot, at: timestamp, emit: emit)
    }

    private mutating func expireReplay(at timestamp: Date) {
        guard let replay else {
            return
        }
        let elapsed = timestamp.timeIntervalSince(replay.startedAt)
        if elapsed < 0 || elapsed >= Self.replayWindowDuration {
            self.replay = nil
        }
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
