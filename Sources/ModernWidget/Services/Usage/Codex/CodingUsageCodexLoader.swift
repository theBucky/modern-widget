import Foundation

struct CodexUsageSource: Sendable {
    let directory: URL
    let home: URL
    let files: [URL]
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
        CodingTokenCounts.codex(
            rawInputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningTokens: reasoningTokens,
            costUSD: CodingUsagePricing.codexCost(
                model: model,
                inputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                outputTokens: outputTokens,
                usesFastPricing: usesFastPricing
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

            for file in source.files {
                let fileKey = CodexUsageFileKey(
                    scope: homePath,
                    path: relativePath(file, from: source.directory)
                )
                guard seenFiles.insert(fileKey).inserted else {
                    continue
                }

                forEachCodexUsageEvent(in: file, usesFastPricing: usesFastPricing) { event in
                    let eventKey = CodexScopedEventKey(scope: homePath, event: event)
                    if seenEvents.insert(eventKey).inserted {
                        accumulator.add(.codex, counts: event.counts, at: event.timestamp)
                    }
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
        let tokenCountNeedle = JSONLineNeedle(#""token_count""#)
        let turnContextNeedle = JSONLineNeedle(#""turn_context""#)
        let threadSpawnNeedle = JSONLineNeedle(#""thread_spawn""#)
        var previousTotals: CodexRawUsage?
        var currentModel: String?
        var replayState = CodexReplayState.idle

        func updatePreviousTotals(from fields: CodexLineFields) {
            if let totalUsage = fields.totalUsage {
                previousTotals = totalUsage
            }
        }

        func appendEvent(from fields: CodexLineFields, at timestamp: Date) {
            let rawUsage = fields.lastUsage ?? fields.totalUsage?.subtracting(previousTotals)
            updatePreviousTotals(from: fields)
            guard let rawUsage, !rawUsage.isEmpty else {
                return
            }

            let model = fields.payloadModel ?? fields.infoModel ?? currentModel ?? "gpt-5"
            currentModel = model
            visit(
                CodexUsageEvent(
                    timestamp: timestamp,
                    model: model,
                    counts: rawUsage.tokenCounts(model: model, usesFastPricing: usesFastPricing)
                )
            )
        }

        func appendPendingReplayEvent() {
            switch replayState {
            case let .pendingReplay(timestamp, fields):
                appendEvent(from: fields, at: timestamp)
                replayState = .idle
            case .awaitingReplay:
                replayState = .idle
            case let .suppressingThenAwaitingReplay(second):
                replayState = .suppressing(second: second)
            case .idle, .suppressing:
                break
            }
        }

        func beginReplay() {
            switch replayState {
            case .idle, .awaitingReplay:
                replayState = .awaitingReplay
            case let .pendingReplay(timestamp, fields):
                appendEvent(from: fields, at: timestamp)
                replayState = .awaitingReplay
            case let .suppressing(second):
                replayState = .suppressingThenAwaitingReplay(second: second)
            case .suppressingThenAwaitingReplay:
                break
            }
        }

        func consumeReplay(_ fields: CodexLineFields, at timestamp: Date) -> Bool {
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
                appendEvent(from: previousFields, at: previousTimestamp)
                replayState = .idle
            case .idle:
                break
            }
            return false
        }

        forEachJSONLine(in: file) { line in
            let hasTokenCount = line.contains(tokenCountNeedle)
            let hasTurnContext = line.contains(turnContextNeedle)
            let isThreadSpawnLine = line.contains(threadSpawnNeedle)
            guard hasTokenCount || hasTurnContext || isThreadSpawnLine else {
                return
            }

            guard let fields = scanCodexLine(line) else { return }

            if isThreadSpawnLine, fields.type == .sessionMeta, fields.hasThreadSpawn {
                beginReplay()
                return
            }

            if fields.type == .turnContext, let model = fields.payloadModel?.nilIfEmpty {
                appendPendingReplayEvent()
                currentModel = model
                return
            }

            guard fields.type == .eventMessage, fields.isTokenCount,
                let timestamp = fields.timestamp
            else {
                return
            }

            if consumeReplay(fields, at: timestamp) {
                return
            }

            appendEvent(from: fields, at: timestamp)
        }

        appendPendingReplayEvent()
    }
}

private func codexSecond(_ timestamp: Date) -> Int64 {
    Int64(timestamp.timeIntervalSince1970.rounded(.down))
}

private func scanCodexLine(_ buffer: UnsafeRawBufferPointer) -> CodexLineFields? {
    guard var scanner = JSONScanner(buffer), scanner.beginObject() else {
        return nil
    }
    var fields = CodexLineFields()
    while let key = scanner.nextKey() {
        if key == "type" {
            fields.type = CodexLineType(scanner.readStringValue())
        } else if key == "timestamp" {
            fields.timestamp = scanner.readTimestamp()
        } else if key == "payload" {
            codexPayload(&scanner, into: &fields)
        } else {
            scanner.skipValue()
        }
    }
    return fields
}

private func codexPayload(_ scanner: inout JSONScanner, into fields: inout CodexLineFields) {
    guard scanner.beginObject() else { return }
    while let key = scanner.nextKey() {
        if key == "type" {
            fields.isTokenCount = scanner.readStringEquals("token_count")
        } else if key == "info" {
            codexInfo(&scanner, into: &fields)
        } else if key == "model" {
            fields.payloadModel = scanner.readString()
        } else if key == "source" {
            fields.hasThreadSpawn = codexSourceHasThreadSpawn(&scanner)
        } else {
            scanner.skipValue()
        }
    }
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
            fields.infoModel = scanner.readString()
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

private enum CodexReplayState {
    case idle
    case awaitingReplay
    case pendingReplay(timestamp: Date, fields: CodexLineFields)
    case suppressing(second: Int64)
    case suppressingThenAwaitingReplay(second: Int64)
}
