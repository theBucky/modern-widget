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

struct CodexUsageEvent {
    let timestamp: Date
    let model: String
    let counts: CodingTokenCounts

    var dedupeKey: CodexUsageEventKey {
        CodexUsageEventKey(
            timestamp: timestamp,
            model: model,
            inputTokens: counts.inputTokens,
            outputTokens: counts.outputTokens,
            cacheReadTokens: counts.cacheReadTokens,
            reasoningTokens: counts.reasoningTokens
        )
    }
}

struct CodexUsageEventKey: Hashable {
    let timestamp: Date
    let model: String
    let inputTokens: UInt64
    let outputTokens: UInt64
    let cacheReadTokens: UInt64
    let reasoningTokens: UInt64
}

struct CodexScopedEventKey: Hashable {
    let scope: String
    let event: CodexUsageEventKey
}

struct CodexRawUsage: Equatable {
    let inputTokens: UInt64
    let cachedInputTokens: UInt64
    let outputTokens: UInt64
    let reasoningTokens: UInt64
    let totalTokens: UInt64

    var isEmpty: Bool {
        inputTokens == 0 && cachedInputTokens == 0 && outputTokens == 0 && reasoningTokens == 0
            && totalTokens == 0
    }

    func tokenCounts(model: String, usesFastPricing: Bool) -> CodingTokenCounts {
        let cachedInputTokens = min(cachedInputTokens, inputTokens)
        return CodingTokenCounts.codex(
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
            reasoningTokens: reasoningTokens.saturatingSubtract(previous?.reasoningTokens ?? 0),
            totalTokens: totalTokens.saturatingSubtract(previous?.totalTokens ?? 0)
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

        for source in sources {
            let usesFastPricing = codexConfigRequestsFastPricing(
                source.home.appendingPathComponent("config.toml"))

            for file in source.files {
                let fileKey = CodexUsageFileKey(
                    scope: source.home.path,
                    path: relativePath(file, from: source.directory)
                )
                guard seenFiles.insert(fileKey).inserted else {
                    continue
                }

                for event in readCodexUsageFile(file, usesFastPricing: usesFastPricing) {
                    let eventKey = CodexScopedEventKey(
                        scope: source.home.path,
                        event: event.dedupeKey
                    )
                    guard seenEvents.insert(eventKey).inserted else {
                        continue
                    }
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
        var directories: [URL] = []

        if let rawPaths = environment["CODEX_HOME"],
            !rawPaths.trimmingCharacters(in: .whitespaces).isEmpty
        {
            directories.append(
                contentsOf:
                    rawPaths
                    .split(separator: ",")
                    .map {
                        expandHomePath(String($0).trimmingCharacters(in: .whitespaces))
                            .standardizedFileURL
                    }
            )
        } else {
            directories.append(homeDirectory.appendingPathComponent(".codex"))
        }

        return directories.uniquedByPath()
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

    func readCodexUsageFile(
        _ file: URL,
        usesFastPricing: Bool
    ) -> [CodexUsageEvent] {
        let fallbackTimestamp = fileModifiedDate(file) ?? .distantPast
        let tokenCountNeedle = [UInt8](#""token_count""#.utf8)
        let turnContextNeedle = [UInt8](#""turn_context""#.utf8)
        let usageNeedle = [UInt8](#""usage""#.utf8)
        var events: [CodexUsageEvent] = []
        var previousTotals: CodexRawUsage?
        var currentModel: String?

        forEachJSONLine(in: file) { line in
            if !line.contains(tokenCountNeedle), !line.contains(turnContextNeedle),
                !line.contains(usageNeedle)
            {
                return
            }

            guard let fields = scanCodexLine(line) else { return }

            if fields.type == "turn_context", let model = fields.payloadModel.resolved {
                currentModel = model
                return
            }

            if fields.type == "event_msg", fields.payloadType == "token_count", fields.hasInfo,
                let timestamp = fields.topTimestamp
            {
                let totalUsage = fields.infoTotal
                let rawUsage = fields.infoLast ?? totalUsage?.subtracting(previousTotals)
                if let totalUsage {
                    previousTotals = totalUsage
                }
                if let rawUsage, !rawUsage.isEmpty {
                    let model =
                        fields.payloadModel.resolved ?? fields.infoModel.resolved ?? currentModel
                        ?? "gpt-5"
                    currentModel = model
                    events.append(
                        CodexUsageEvent(
                            timestamp: timestamp,
                            model: model,
                            counts: rawUsage.tokenCounts(
                                model: model, usesFastPricing: usesFastPricing)
                        )
                    )
                    return
                }
            }

            if let rawUsage = fields.headlessUsage, !rawUsage.isEmpty {
                let timestamp = fields.headlessTimestamp ?? fallbackTimestamp
                let model = fields.headlessModel ?? currentModel ?? "gpt-5"
                currentModel = model
                events.append(
                    CodexUsageEvent(
                        timestamp: timestamp,
                        model: model,
                        counts: rawUsage.tokenCounts(model: model, usesFastPricing: usesFastPricing)
                    )
                )
            }
        }

        return events
    }
}

private func scanCodexLine(_ buffer: UnsafeRawBufferPointer) -> CodexLineFields? {
    guard var scanner = JSONScanner(buffer), scanner.beginObject() else {
        return nil
    }
    var fields = CodexLineFields()
    while let key = scanner.nextKey() {
        if key == "type" {
            fields.type = scanner.readString()
        } else if key == "timestamp" {
            fields.topTimestamp = scanner.readTimestamp()
        } else if (key == "created_at" || key == "createdAt"), fields.topCreatedAt == nil {
            fields.topCreatedAt = scanner.readTimestamp()
        } else if key == "usage" {
            fields.topUsage = codexUsage(&scanner)
        } else if key == "payload" {
            codexPayload(&scanner, into: &fields)
        } else if key == "data" {
            fields.data = codexContainer(&scanner)
        } else if key == "result" {
            fields.result = codexContainer(&scanner)
        } else if key == "response" {
            fields.response = codexContainer(&scanner)
        } else if fields.topModel.consume(key: key, from: &scanner) {
            // model / model_name / metadata
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
            fields.payloadType = scanner.readString()
        } else if key == "info" {
            codexInfo(&scanner, into: &fields)
        } else if fields.payloadModel.consume(key: key, from: &scanner) {
            // model / model_name / metadata
        } else {
            scanner.skipValue()
        }
    }
}

private func codexInfo(_ scanner: inout JSONScanner, into fields: inout CodexLineFields) {
    guard scanner.beginObject() else { return }
    fields.hasInfo = true
    while let key = scanner.nextKey() {
        if key == "total_token_usage" {
            fields.infoTotal = codexUsage(&scanner)
        } else if key == "last_token_usage" {
            fields.infoLast = codexUsage(&scanner)
        } else if fields.infoModel.consume(key: key, from: &scanner) {
            // model / model_name / metadata
        } else {
            scanner.skipValue()
        }
    }
}

/// Reads a `data`/`result`/`response` container's usage, model, and timestamp.
private func codexContainer(_ scanner: inout JSONScanner) -> CodexContainer? {
    guard scanner.beginObject() else { return nil }
    var container = CodexContainer()
    var model = CodexModelFields()
    var createdAt: Date?
    while let key = scanner.nextKey() {
        if key == "usage" {
            container.usage = codexUsage(&scanner)
        } else if key == "timestamp" {
            container.timestamp = scanner.readTimestamp()
        } else if (key == "created_at" || key == "createdAt"), createdAt == nil {
            createdAt = scanner.readTimestamp()
        } else if model.consume(key: key, from: &scanner) {
            // model / model_name / metadata
        } else {
            scanner.skipValue()
        }
    }
    container.model = model.resolved
    container.timestamp = container.timestamp ?? createdAt
    return container
}

/// Reads a usage object, returning `nil` when the value is not an object so a
/// missing usage key stays distinguishable from an all-zero one.
private func codexUsage(_ scanner: inout JSONScanner) -> CodexRawUsage? {
    guard scanner.beginObject() else { return nil }
    var inputTokens: UInt64?
    var promptTokens: UInt64?
    var input: UInt64?
    var outputTokens: UInt64?
    var completionTokens: UInt64?
    var output: UInt64?
    var reasoningOutput: UInt64?
    var reasoning: UInt64?
    var cachedInput: UInt64?
    var cacheReadInput: UInt64?
    var cached: UInt64?
    var total: UInt64?
    while let key = scanner.nextKey() {
        if key == "input_tokens" {
            inputTokens = scanner.readUInt64()
        } else if key == "prompt_tokens" {
            promptTokens = scanner.readUInt64()
        } else if key == "input" {
            input = scanner.readUInt64()
        } else if key == "output_tokens" {
            outputTokens = scanner.readUInt64()
        } else if key == "completion_tokens" {
            completionTokens = scanner.readUInt64()
        } else if key == "output" {
            output = scanner.readUInt64()
        } else if key == "reasoning_output_tokens" {
            reasoningOutput = scanner.readUInt64()
        } else if key == "reasoning_tokens" {
            reasoning = scanner.readUInt64()
        } else if key == "cached_input_tokens" {
            cachedInput = scanner.readUInt64()
        } else if key == "cache_read_input_tokens" {
            cacheReadInput = scanner.readUInt64()
        } else if key == "cached_tokens" {
            cached = scanner.readUInt64()
        } else if key == "total_tokens" {
            total = scanner.readUInt64()
        } else {
            scanner.skipValue()
        }
    }
    return CodexRawUsage(
        inputTokens: inputTokens ?? promptTokens ?? input ?? 0,
        cachedInputTokens: cachedInput ?? cacheReadInput ?? cached ?? 0,
        outputTokens: outputTokens ?? completionTokens ?? output ?? 0,
        reasoningTokens: reasoningOutput ?? reasoning ?? 0,
        totalTokens: total ?? 0
    )
}

/// A `model` / `model_name` / `metadata.model` triple resolved in the loader's order.
private struct CodexModelFields {
    var model: String?
    var modelName: String?
    var metadata: String?

    var resolved: String? { model?.nilIfEmpty ?? modelName?.nilIfEmpty ?? metadata?.nilIfEmpty }

    mutating func consume(key: JSONKey, from scanner: inout JSONScanner) -> Bool {
        if key == "model" {
            model = scanner.readString()
        } else if key == "model_name" {
            modelName = scanner.readString()
        } else if key == "metadata" {
            guard scanner.beginObject() else { return true }
            while let inner = scanner.nextKey() {
                if inner == "model" {
                    metadata = scanner.readString()
                } else {
                    scanner.skipValue()
                }
            }
        } else {
            return false
        }
        return true
    }
}

/// The usage, model, and timestamp of one container object.
private struct CodexContainer {
    var usage: CodexRawUsage?
    var model: String?
    var timestamp: Date?
}

/// Scalar fields pulled from one Codex log line. Models the three extraction paths the
/// loader needs: `turn_context` model carry-over, `token_count` events from
/// `payload.info`, and headless usage from the line's own `usage`/`data`/`result`/
/// `response` containers (object first, then those three in order).
private struct CodexLineFields {
    var type: String?
    var topTimestamp: Date?
    var topCreatedAt: Date?
    var topModel = CodexModelFields()
    var topUsage: CodexRawUsage?

    var payloadType: String?
    var payloadModel = CodexModelFields()
    var hasInfo = false
    var infoTotal: CodexRawUsage?
    var infoLast: CodexRawUsage?
    var infoModel = CodexModelFields()

    var data: CodexContainer?
    var result: CodexContainer?
    var response: CodexContainer?

    /// First container with a usage key, object before `data`/`result`/`response`.
    var headlessUsage: CodexRawUsage? {
        topUsage ?? data?.usage ?? result?.usage ?? response?.usage
    }
    var headlessModel: String? {
        topModel.resolved ?? data?.model ?? result?.model ?? response?.model
    }
    var headlessTimestamp: Date? {
        topTimestamp ?? topCreatedAt ?? data?.timestamp ?? result?.timestamp ?? response?.timestamp
    }
}
