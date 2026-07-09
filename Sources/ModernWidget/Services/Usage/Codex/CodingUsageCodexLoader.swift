import Foundation

struct CodexUsageSource: Sendable {
    let directory: URL
    let home: URL
    let files: [CodingUsageFile]
}

struct CodexUsageFileKey: Hashable {
    let scope: String
    let path: String
}

struct CodexUsageEvent: Hashable {
    let timestamp: Date
    let model: String
    let counts: CodingTokenCounts
}

struct CodexScopedEventKey: Hashable {
    let scope: String
    let event: CodexUsageEvent
}

struct CodexRawUsage {
    let inputTokens: UInt64
    let cachedInputTokens: UInt64
    let outputTokens: UInt64
    let reasoningTokens: UInt64

    init(
        inputTokens: UInt64,
        cachedInputTokens: UInt64,
        outputTokens: UInt64,
        reasoningTokens: UInt64
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = min(cachedInputTokens, inputTokens)
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
    }

    var isEmpty: Bool {
        inputTokens == 0 && cachedInputTokens == 0 && outputTokens == 0 && reasoningTokens == 0
    }

    func tokenCounts(model: String, usesFastPricing: Bool) -> CodingTokenCounts {
        let billedInputTokens = inputTokens - cachedInputTokens
        return CodingTokenCounts(
            inputTokens: billedInputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cachedInputTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: inputTokens.saturatingAdd(outputTokens),
            costUSD: CodingUsagePricing.cost(
                model: model,
                tokens: CodingUsageBillableTokens(
                    input: billedInputTokens,
                    output: outputTokens,
                    cacheRead: cachedInputTokens,
                    usesFastPricing: usesFastPricing
                )
            )
        )
    }

    func subtracting(_ previous: CodexRawUsage?) -> CodexRawUsage {
        CodexRawUsage(
            inputTokens: inputTokens.saturatingSubtract(previous?.inputTokens ?? 0),
            cachedInputTokens: cachedInputTokens.saturatingSubtract(
                previous?.cachedInputTokens ?? 0),
            outputTokens: outputTokens.saturatingSubtract(previous?.outputTokens ?? 0),
            reasoningTokens: reasoningTokens.saturatingSubtract(previous?.reasoningTokens ?? 0)
        )
    }
}

extension CodingUsageLoader {
    func loadCodexUsage(
        sources: [CodexUsageSource],
        into accumulator: inout CodingUsageAccumulator
    ) {
        // Active sessions are scanned before archived ones; within a home the first
        // occurrence of a file or event wins, so archived duplicates are dropped.
        var seenFiles: Set<CodexUsageFileKey> = []
        var seenEvents: Set<CodexScopedEventKey> = []
        var fastPricingByHome: [String: Bool] = [:]

        for source in sources {
            let homePath = source.home.path
            let usesFastPricing: Bool
            if let cached = fastPricingByHome[homePath] {
                usesFastPricing = cached
            } else {
                usesFastPricing = codexConfigRequestsFastPricing(
                    source.home.appendingPathComponent("config.toml"))
                fastPricingByHome[homePath] = usesFastPricing
            }

            let files = source.files.filter { file in
                let fileKey = CodexUsageFileKey(
                    scope: homePath,
                    path: relativePath(file.url, from: source.directory)
                )
                return seenFiles.insert(fileKey).inserted
            }

            // Sessions parse in parallel; the cross-file event dedupe below stays
            // sequential in file order so active files keep beating archived ones.
            let eventLists = concurrentMap(files) { file in
                var events: [CodexUsageEvent] = []
                forEachCodexUsageEvent(in: file.url, usesFastPricing: usesFastPricing) {
                    events.append($0)
                }
                return events
            }

            for event in eventLists.joined() {
                let eventKey = CodexScopedEventKey(scope: homePath, event: event)
                if seenEvents.insert(eventKey).inserted {
                    accumulator.add(.codex, counts: event.counts, at: event.timestamp)
                }
            }
        }
    }

    func codexUsageSources(homes: [URL], scope: CodingUsageDateScope) -> [CodexUsageSource] {
        homes.flatMap {
            home -> [CodexUsageSource] in
            let sessions = home.appendingPathComponent("sessions")
            let archivedSessions = home.appendingPathComponent("archived_sessions")
            var directories: [URL] = []

            if isDirectory(sessions) {
                directories.append(sessions)
            }
            if isDirectory(archivedSessions) {
                directories.append(archivedSessions)
            }
            if directories.isEmpty {
                directories.append(home)
            }

            return directories.map {
                CodexUsageSource(
                    directory: $0,
                    home: home,
                    files: usageFiles(in: $0, modifiedSince: scope.history.start)
                )
            }
        }
    }

    func codexHomeDirectories() -> [URL] {
        configuredDirectories(environmentKey: "CODEX_HOME") {
            [homeDirectory.appendingPathComponent(".codex")]
        }
        .filter(isDirectory)
    }

    func codexFingerprintFiles(homes: [URL]) -> [URL] {
        homes.map {
            $0.appendingPathComponent("config.toml")
        }
    }

    func codexConfigRequestsFastPricing(_ file: URL) -> Bool {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return false
        }
        for line in text.split(separator: "\n") {
            let setting =
                line.split(separator: "#", maxSplits: 1).first?.trimmingCharacters(
                    in: .whitespacesAndNewlines) ?? ""
            if setting.hasPrefix("[") {
                return false
            }
            guard let separator = setting.firstIndex(of: "=") else {
                continue
            }
            let key = setting[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = setting[setting.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: ["\"", "'"])
            if key == "service_tier" {
                return value == "fast" || value == "priority"
            }
        }
        return false
    }

    func forEachCodexUsageEvent(
        in file: URL,
        usesFastPricing: Bool,
        visit: (CodexUsageEvent) -> Void
    ) {
        var session = CodexSessionState(usesFastPricing: usesFastPricing)

        forEachJSONLine(in: file) { buffer in
            // Codex lines lead with `timestamp` and `type`, so the scanner classifies a
            // line from its first bytes and abandons the irrelevant majority, payloads
            // untouched. A needle prefilter would rescan every full line instead.
            guard let line = scanCodexLine(buffer) else { return }
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
}

private func nonEmptyString(_ value: String?) -> String? {
    value?.isEmpty == false ? value : nil
}

/// Parses one relevant Codex line, stopping as soon as its type proves irrelevant.
private func scanCodexLine(_ buffer: UnsafeRawBufferPointer) -> CodexLine? {
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
            fields.timestamp = scanner.readTimestamp()
        } else if key == "payload" {
            guard codexPayload(&scanner, into: &fields) else {
                return nil
            }
        } else {
            scanner.skipValue()
        }
    }
    return fields.line
}

/// Returns `false` when the payload proves the line irrelevant, so the caller can
/// abandon it mid-scan. Bailing on a non-token-count `payload.type` is only safe once
/// the top-level type is known to be `event_msg`; a payload that precedes the type
/// (never observed, but legal JSON) is scanned in full.
private func codexPayload(_ scanner: inout JSONScanner, into fields: inout CodexLineFields) -> Bool
{
    guard scanner.beginObject() else { return true }
    while let key = scanner.nextKey() {
        if key == "type" {
            fields.isTokenCount = scanner.readStringEquals("token_count")
            if !fields.isTokenCount, fields.type == .eventMessage {
                return false
            }
        } else if key == "info" {
            codexInfo(&scanner, into: &fields)
        } else if key == "model" {
            fields.payloadModel = nonEmptyString(scanner.readString())
        } else if key == "id" {
            fields.sessionID = nonEmptyString(scanner.readString()) ?? fields.sessionID
        } else if key == "source" {
            fields.threadSpawnParentID =
                codexThreadSpawnParentID(&scanner) ?? fields.threadSpawnParentID
        } else {
            scanner.skipValue()
        }
    }
    return true
}

private func codexThreadSpawnParentID(_ scanner: inout JSONScanner) -> String? {
    guard scanner.beginObject() else { return nil }
    var parentID: String?
    while let key = scanner.nextKey() {
        if key == "subagent" {
            parentID = codexSubagentParentID(&scanner) ?? parentID
        } else {
            scanner.skipValue()
        }
    }
    return parentID
}

private func codexSubagentParentID(_ scanner: inout JSONScanner) -> String? {
    guard scanner.beginObject() else { return nil }
    var parentID: String?
    while let key = scanner.nextKey() {
        if key == "thread_spawn" {
            parentID = codexParentThreadID(&scanner) ?? parentID
        } else {
            scanner.skipValue()
        }
    }
    return parentID
}

private func codexParentThreadID(_ scanner: inout JSONScanner) -> String? {
    guard scanner.beginObject() else { return nil }
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

private func codexInfo(_ scanner: inout JSONScanner, into fields: inout CodexLineFields) {
    guard scanner.beginObject() else { return }
    while let key = scanner.nextKey() {
        if key == "last_token_usage" {
            fields.lastUsage = codexUsage(&scanner)
        } else if key == "total_token_usage" {
            fields.totalUsage = codexUsage(&scanner)
        } else if key == "model" {
            fields.infoModel = nonEmptyString(scanner.readString())
        } else {
            scanner.skipValue()
        }
    }
}

/// Reads a usage object, returning `nil` when the value is not an object so a
/// missing usage key stays distinguishable from an all-zero one.
/// Codex rollouts currently omit the API's `cache_write_tokens`. Do not infer writes
/// from uncached input because cache misses do not imply cache writes.
private func codexUsage(_ scanner: inout JSONScanner) -> CodexRawUsage? {
    guard scanner.beginObject() else { return nil }
    var inputTokens: UInt64 = 0
    var cachedInputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var reasoningTokens: UInt64 = 0
    while let key = scanner.nextKey() {
        if key == "input_tokens" {
            inputTokens = scanner.readUInt64() ?? 0
        } else if key == "cached_input_tokens" {
            cachedInputTokens = scanner.readUInt64() ?? 0
        } else if key == "output_tokens" {
            outputTokens = scanner.readUInt64() ?? 0
        } else if key == "reasoning_output_tokens" {
            reasoningTokens = scanner.readUInt64() ?? 0
        } else {
            scanner.skipValue()
        }
    }
    return CodexRawUsage(
        inputTokens: inputTokens,
        cachedInputTokens: cachedInputTokens,
        outputTokens: outputTokens,
        reasoningTokens: reasoningTokens
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
    let threadSpawnParentID: String?

    init?(id: String?, threadSpawnParentID: String?) {
        guard id != nil || threadSpawnParentID != nil else { return nil }
        self.id = id
        self.threadSpawnParentID = threadSpawnParentID
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
    var timestamp: Date?

    var isTokenCount = false
    var sessionID: String?
    var threadSpawnParentID: String?
    var payloadModel: String?
    var lastUsage: CodexRawUsage?
    var totalUsage: CodexRawUsage?
    var infoModel: String?

    var line: CodexLine? {
        guard let timestamp else { return nil }
        switch type {
        case .sessionMeta:
            guard
                let sessionMeta = CodexSessionMeta(
                    id: sessionID,
                    threadSpawnParentID: threadSpawnParentID
                )
            else { return nil }
            return .sessionMeta(sessionMeta, at: timestamp)
        case .turnContext:
            guard let payloadModel else { return nil }
            return .turnContext(model: payloadModel, at: timestamp)
        case .eventMessage:
            guard isTokenCount else { return nil }
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

/// Folds a session's token-count lines into usage events while preserving the cumulative
/// baseline across confirmed replay windows. Codex writes the current rollout's metadata
/// first, then may copy parent metadata into fork history. Only the first `thread_spawn`
/// source belongs to this rollout; a later matching identity confirms its replay.
private struct CodexSessionState {
    private struct Replay {
        enum Phase {
            case awaitingParent(id: String)
            case replaying
        }

        let startedAt: Date
        let phase: Phase
    }

    /// Model assumed when a Codex line names none, so pricing has something to resolve.
    private static let codexDefaultModel = "gpt-5"
    private static let replayWindowDuration: TimeInterval = 1

    private let usesFastPricing: Bool
    private var previousTotals: CodexRawUsage?
    private var currentModel: String?
    private var hasSessionHeader = false
    private var replay: Replay?

    init(usesFastPricing: Bool) {
        self.usesFastPricing = usesFastPricing
    }

    mutating func onSessionMeta(_ metadata: CodexSessionMeta, at timestamp: Date) {
        expireReplay(at: timestamp)

        if !hasSessionHeader {
            hasSessionHeader = true
            guard let parentID = metadata.threadSpawnParentID else { return }
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
        _ snapshot: CodexTokenSnapshot, at timestamp: Date, emit: (CodexUsageEvent) -> Void
    ) {
        expireReplay(at: timestamp)
        if let replay, case .replaying = replay.phase {
            updatePreviousTotals(from: snapshot)
            return
        }
        replay = nil
        emitEvent(from: snapshot, at: timestamp, emit: emit)
    }

    private mutating func expireReplay(at timestamp: Date) {
        guard let replay else { return }
        let elapsed = timestamp.timeIntervalSince(replay.startedAt)
        if elapsed < 0 || elapsed >= Self.replayWindowDuration {
            self.replay = nil
        }
    }

    private mutating func emitEvent(
        from snapshot: CodexTokenSnapshot, at timestamp: Date,
        emit: (CodexUsageEvent) -> Void
    ) {
        let rawUsage = snapshot.lastUsage ?? snapshot.totalUsage?.subtracting(previousTotals)
        updatePreviousTotals(from: snapshot)
        guard let rawUsage, !rawUsage.isEmpty else {
            return
        }

        let model = snapshot.model ?? currentModel ?? Self.codexDefaultModel
        currentModel = model
        emit(
            CodexUsageEvent(
                timestamp: timestamp,
                model: model,
                counts: rawUsage.tokenCounts(model: model, usesFastPricing: usesFastPricing)
            )
        )
    }

    private mutating func updatePreviousTotals(from snapshot: CodexTokenSnapshot) {
        if let totalUsage = snapshot.totalUsage {
            previousTotals = totalUsage
        }
    }
}
