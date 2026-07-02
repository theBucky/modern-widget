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

    func codexUsageSources(scope: CodingUsageDateScope) -> [CodexUsageSource] {
        codexHomeDirectories().flatMap {
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
    }

    func codexFingerprintFiles() -> [URL] {
        codexHomeDirectories().map {
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
        var deduper = CodexReplayDeduper(usesFastPricing: usesFastPricing)

        forEachJSONLine(in: file) { line in
            // Codex lines lead with `timestamp` and `type`, so the scanner classifies a
            // line from its first bytes and abandons the irrelevant majority, payloads
            // untouched. A needle prefilter would rescan every full line instead.
            guard let fields = scanCodexLine(line) else { return }

            if fields.type == .sessionMeta, fields.hasThreadSpawn {
                deduper.onThreadSpawn(emit: visit)
                return
            }

            if fields.type == .turnContext, let model = fields.payloadModel {
                deduper.onTurnContext(model: model, emit: visit)
                return
            }

            guard fields.type == .eventMessage, fields.isTokenCount,
                let timestamp = fields.timestamp
            else {
                return
            }

            deduper.onTokenCount(fields, at: timestamp, emit: visit)
        }

        deduper.finish(emit: visit)
    }
}

private func codexSecond(_ timestamp: Date) -> Int64 {
    Int64(timestamp.timeIntervalSince1970.rounded(.down))
}

/// Empty model strings count as missing everywhere: they must neither reach pricing
/// nor overwrite the carried-over `currentModel`.
private func nonEmptyString(_ value: String?) -> String? {
    value?.isEmpty == false ? value : nil
}

/// Extracts the fields of one Codex log line, returning `nil` as soon as the line
/// proves irrelevant: an uninteresting top-level `type` stops before the payload, and
/// a non-token-count `event_msg` stops at the payload's leading `type`.
private func scanCodexLine(_ buffer: UnsafeRawBufferPointer) -> CodexLineFields? {
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
    return fields
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
        } else if key == "source" {
            fields.hasThreadSpawn = codexSourceHasThreadSpawn(&scanner)
        } else {
            scanner.skipValue()
        }
    }
    return true
}

private func codexSourceHasThreadSpawn(_ scanner: inout JSONScanner) -> Bool {
    guard scanner.beginObject() else { return false }
    var hasThreadSpawn = false
    while let key = scanner.nextKey() {
        if key == "subagent" {
            hasThreadSpawn = codexSubagentHasThreadSpawn(&scanner) || hasThreadSpawn
        } else {
            scanner.skipValue()
        }
    }
    return hasThreadSpawn
}

private func codexSubagentHasThreadSpawn(_ scanner: inout JSONScanner) -> Bool {
    guard scanner.beginObject() else { return false }
    var hasThreadSpawn = false
    while let key = scanner.nextKey() {
        if key == "thread_spawn" {
            hasThreadSpawn = true
        }
        scanner.skipValue()
    }
    return hasThreadSpawn
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

/// Scalar fields pulled from one Codex log line: `turn_context` model carry-over and
/// `event_msg` token counts from `payload.info`.
private struct CodexLineFields {
    var type: CodexLineType = .other
    var timestamp: Date?

    var isTokenCount = false
    var hasThreadSpawn = false
    var payloadModel: String?
    var lastUsage: CodexRawUsage?
    var totalUsage: CodexRawUsage?
    var infoModel: String?
}

/// Tracks the subagent replay window. A real
/// `session_meta.payload.source.subagent.thread_spawn` is followed by the parent's
/// cumulative snapshots replayed within the same second; those repeats must be dropped,
/// while a genuinely new event in a later second still counts. The first snapshot after a
/// spawn is held until a same-second sibling proves it is replay, or a later second, turn
/// context, or end of file proves it is real and emits it.
private enum CodexReplayState {
    /// No spawn pending; events are emitted normally.
    case idle
    /// A spawn was seen; waiting for the first replayed snapshot.
    case awaitingReplay
    /// Holding one snapshot that is replay if a same-second sibling follows, otherwise real.
    case pendingReplay(timestamp: Date, fields: CodexLineFields)
    /// Dropping snapshots that share `second` with the suppressed replay.
    case suppressing(second: Int64)
    /// Suppressing `second`, with another spawn awaiting replay once that second passes.
    case suppressingThenAwaitingReplay(second: Int64)
}

/// Folds a session's token-count lines into deduplicated usage events. The caller
/// classifies each line; this type owns the running totals, the carried-over model,
/// and the `CodexReplayState` machine that drops the cumulative snapshots a subagent
/// thread-spawn replays within the same second while keeping genuinely new events.
private struct CodexReplayDeduper {
    /// Model assumed when a Codex line names none, so pricing has something to resolve.
    private static let codexDefaultModel = "gpt-5"

    private let usesFastPricing: Bool
    private var previousTotals: CodexRawUsage?
    private var currentModel: String?
    private var replayState = CodexReplayState.idle

    init(usesFastPricing: Bool) {
        self.usesFastPricing = usesFastPricing
    }

    /// A `session_meta` line whose source is a subagent thread-spawn.
    mutating func onThreadSpawn(emit: (CodexUsageEvent) -> Void) {
        switch replayState {
        case .idle, .awaitingReplay:
            replayState = .awaitingReplay
        case let .pendingReplay(timestamp, fields):
            emitEvent(from: fields, at: timestamp, emit: emit)
            replayState = .awaitingReplay
        case let .suppressing(second):
            replayState = .suppressingThenAwaitingReplay(second: second)
        case .suppressingThenAwaitingReplay:
            break
        }
    }

    /// A `turn_context` line carrying the model for subsequent events.
    mutating func onTurnContext(model: String, emit: (CodexUsageEvent) -> Void) {
        flushPendingReplay(emit: emit)
        currentModel = model
    }

    /// An `event_msg` `token_count` line.
    mutating func onTokenCount(
        _ fields: CodexLineFields, at timestamp: Date, emit: (CodexUsageEvent) -> Void
    ) {
        if consumeReplay(fields, at: timestamp, emit: emit) {
            return
        }
        emitEvent(from: fields, at: timestamp, emit: emit)
    }

    /// Flushes any snapshot still held back when the session ends.
    mutating func finish(emit: (CodexUsageEvent) -> Void) {
        flushPendingReplay(emit: emit)
    }

    private mutating func flushPendingReplay(emit: (CodexUsageEvent) -> Void) {
        switch replayState {
        case let .pendingReplay(timestamp, fields):
            replayState = .idle
            emitEvent(from: fields, at: timestamp, emit: emit)
        case .awaitingReplay:
            replayState = .idle
        case let .suppressingThenAwaitingReplay(second):
            replayState = .suppressing(second: second)
        case .idle, .suppressing:
            break
        }
    }

    private mutating func consumeReplay(
        _ fields: CodexLineFields, at timestamp: Date, emit: (CodexUsageEvent) -> Void
    ) -> Bool {
        let second = codexSecond(timestamp)
        switch replayState {
        case let .suppressing(activeSecond):
            if activeSecond == second {
                updatePreviousTotals(from: fields)
                return true
            }
            replayState = .idle
        case let .suppressingThenAwaitingReplay(activeSecond):
            if activeSecond == second {
                updatePreviousTotals(from: fields)
                return true
            }
            replayState = .pendingReplay(timestamp: timestamp, fields: fields)
            return true
        case .awaitingReplay:
            replayState = .pendingReplay(timestamp: timestamp, fields: fields)
            return true
        case let .pendingReplay(previousTimestamp, previousFields):
            if codexSecond(previousTimestamp) == second {
                updatePreviousTotals(from: previousFields)
                updatePreviousTotals(from: fields)
                replayState = .suppressing(second: second)
                return true
            }
            emitEvent(from: previousFields, at: previousTimestamp, emit: emit)
            replayState = .idle
        case .idle:
            break
        }
        return false
    }

    private mutating func emitEvent(
        from fields: CodexLineFields, at timestamp: Date, emit: (CodexUsageEvent) -> Void
    ) {
        let rawUsage = fields.lastUsage ?? fields.totalUsage?.subtracting(previousTotals)
        updatePreviousTotals(from: fields)
        guard let rawUsage, !rawUsage.isEmpty else {
            return
        }

        let model =
            fields.payloadModel ?? fields.infoModel ?? currentModel ?? Self.codexDefaultModel
        currentModel = model
        emit(
            CodexUsageEvent(
                timestamp: timestamp,
                model: model,
                counts: rawUsage.tokenCounts(model: model, usesFastPricing: usesFastPricing)
            )
        )
    }

    private mutating func updatePreviousTotals(from fields: CodexLineFields) {
        if let totalUsage = fields.totalUsage {
            previousTotals = totalUsage
        }
    }
}
