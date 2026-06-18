import Foundation

struct CodexUsageSource {
    let directory: URL
    let home: URL
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
            inputTokens: inputTokens,
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
        scope: CodingUsageDateScope,
        into accumulator: inout CodingUsageAccumulator
    ) {
        // Active sessions are scanned before archived ones; within a home the first
        // occurrence of a file or event wins, so archived duplicates are dropped.
        var seenFiles: Set<CodexUsageFileKey> = []
        var seenEvents: Set<CodexScopedEventKey> = []

        for source in codexUsageSources() {
            let usesFastPricing = codexConfigRequestsFastPricing(
                source.home.appendingPathComponent("config.toml"))

            for file in usageFiles(in: source.directory, modifiedSince: scope.history.start) {
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

    func codexUsageSources() -> [CodexUsageSource] {
        codexHomeDirectories().flatMap {
            home -> [CodexUsageSource] in
            let sessions = home.appendingPathComponent("sessions")
            let archivedSessions = home.appendingPathComponent("archived_sessions")
            var sources: [CodexUsageSource] = []

            if isDirectory(sessions) {
                sources.append(CodexUsageSource(directory: sessions, home: home))
            }
            if isDirectory(archivedSessions) {
                sources.append(CodexUsageSource(directory: archivedSessions, home: home))
            }
            if sources.isEmpty {
                sources.append(CodexUsageSource(directory: home, home: home))
            }
            return sources
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
        let tokenCountNeedle = Data(#""token_count""#.utf8)
        let turnContextNeedle = Data(#""turn_context""#.utf8)
        let usageNeedle = Data(#""usage""#.utf8)
        var events: [CodexUsageEvent] = []
        var previousTotals: CodexRawUsage?
        var currentModel: String?

        forEachJSONLine(in: file) { line in
            if line.range(of: tokenCountNeedle) == nil
                && line.range(of: turnContextNeedle) == nil
                && line.range(of: usageNeedle) == nil
            {
                return
            }

            guard let object = parseJSONObject(line) else { return }

            if let nextModel = codexTurnContextModel(from: object) {
                currentModel = nextModel
                return
            }

            if let event = codexTokenCountEvent(
                from: object,
                previousTotals: &previousTotals,
                currentModel: &currentModel,
                usesFastPricing: usesFastPricing
            ) {
                events.append(event)
                return
            }

            if let event = codexHeadlessEvent(
                from: object,
                fallbackTimestamp: fallbackTimestamp,
                currentModel: &currentModel,
                usesFastPricing: usesFastPricing
            ) {
                events.append(event)
            }
        }

        return events
    }

    func codexTokenCountEvent(
        from object: JSONObject,
        previousTotals: inout CodexRawUsage?,
        currentModel: inout String?,
        usesFastPricing: Bool
    ) -> CodexUsageEvent? {
        guard string(object["type"]) == "event_msg",
            let timestamp = parseTimestamp(object["timestamp"]),
            let payload = dictionary(object["payload"]),
            string(payload["type"]) == "token_count",
            let info = dictionary(payload["info"])
        else {
            return nil
        }

        let totalUsage = codexRawUsage(from: dictionary(info["total_token_usage"]))
        if let totalUsage, totalUsage == previousTotals {
            return nil
        }

        let rawUsage =
            codexRawUsage(from: dictionary(info["last_token_usage"]))
            ?? totalUsage?.subtracting(previousTotals)

        if let totalUsage {
            previousTotals = totalUsage
        }

        guard let rawUsage, !rawUsage.isEmpty else {
            return nil
        }

        let model = codexModel(from: payload) ?? codexModel(from: info) ?? currentModel ?? "gpt-5"
        currentModel = model

        return CodexUsageEvent(
            timestamp: timestamp,
            model: model,
            counts: rawUsage.tokenCounts(model: model, usesFastPricing: usesFastPricing)
        )
    }

    func codexHeadlessEvent(
        from object: JSONObject,
        fallbackTimestamp: Date,
        currentModel: inout String?,
        usesFastPricing: Bool
    ) -> CodexUsageEvent? {
        let containers = codexContainers(from: object)
        guard
            let rawUsage = containers.compactMap({
                codexRawUsage(from: dictionary($0["usage"]))
            }).first,
            !rawUsage.isEmpty
        else {
            return nil
        }
        let timestamp = containers.compactMap(codexTimestamp).first ?? fallbackTimestamp
        let model = containers.compactMap(codexModel).first ?? currentModel ?? "gpt-5"

        currentModel = model
        return CodexUsageEvent(
            timestamp: timestamp,
            model: model,
            counts: rawUsage.tokenCounts(model: model, usesFastPricing: usesFastPricing)
        )
    }

    func codexTurnContextModel(from object: JSONObject) -> String? {
        guard string(object["type"]) == "turn_context",
            let payload = dictionary(object["payload"])
        else {
            return nil
        }
        return codexModel(from: payload)
    }

    func codexContainers(from object: JSONObject) -> [JSONObject] {
        [object, object["data"], object["result"], object["response"]].compactMap(dictionary)
    }

    func codexRawUsage(from usage: JSONObject?) -> CodexRawUsage? {
        guard let usage else { return nil }

        let inputTokens =
            unsignedInteger(usage["input_tokens"])
            ?? unsignedInteger(usage["prompt_tokens"])
            ?? unsignedInteger(usage["input"])
            ?? 0
        let outputTokens =
            unsignedInteger(usage["output_tokens"])
            ?? unsignedInteger(usage["completion_tokens"])
            ?? unsignedInteger(usage["output"])
            ?? 0
        let reasoningTokens =
            unsignedInteger(usage["reasoning_output_tokens"])
            ?? unsignedInteger(usage["reasoning_tokens"])
            ?? 0
        let cachedInputTokens =
            unsignedInteger(usage["cached_input_tokens"])
            ?? unsignedInteger(usage["cache_read_input_tokens"])
            ?? unsignedInteger(usage["cached_tokens"])
            ?? 0
        return CodexRawUsage(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: unsignedInteger(usage["total_tokens"]) ?? 0
        )
    }

    func codexModel(from object: JSONObject) -> String? {
        nonEmptyString(object["model"])
            ?? nonEmptyString(object["model_name"])
            ?? dictionary(object["metadata"]).flatMap { nonEmptyString($0["model"]) }
    }

    func codexTimestamp(from object: JSONObject) -> Date? {
        parseTimestamp(object["timestamp"])
            ?? parseTimestamp(object["created_at"])
            ?? parseTimestamp(object["createdAt"])
    }
}
