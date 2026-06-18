import Foundation

struct ClaudeUsageEntry {
    let timestamp: Date
    let counts: CodingTokenCounts
    let messageID: String?
    let requestID: String?
    let isSidechain: Bool
}

struct ClaudeDedupeKey: Hashable {
    let messageID: String
    let requestID: String?
}

extension CodingUsageLoader {
    func loadClaudeUsage(
        files: [URL],
        scope: CodingUsageDateScope,
        into accumulator: inout CodingUsageAccumulator
    ) {
        let entries =
            files
            .flatMap(readClaudeUsageFile)
            .filter { scope.historyDay(containing: $0.timestamp) != nil }

        for entry in dedupeClaudeEntries(entries) {
            accumulator.add(.claude, counts: entry.counts, at: entry.timestamp)
        }
    }

    func claudeUsageFiles(scope: CodingUsageDateScope) -> [URL] {
        claudeConfigDirectories().flatMap {
            usageFiles(
                in: $0.appendingPathComponent("projects"), modifiedSince: scope.history.start)
        }
    }

    func claudeConfigDirectories() -> [URL] {
        var directories: [URL] = []

        if let rawPaths = environment["CLAUDE_CONFIG_DIR"],
            !rawPaths.trimmingCharacters(in: .whitespaces).isEmpty
        {
            directories.append(
                contentsOf:
                    rawPaths
                    .split(separator: ",")
                    .map {
                        normalizeClaudeConfigPath(
                            expandHomePath(String($0).trimmingCharacters(in: .whitespaces)))
                    }
            )
        } else {
            let xdgConfigHome =
                environment["XDG_CONFIG_HOME"].map { expandHomePath($0) }
                ?? homeDirectory.appendingPathComponent(".config")

            directories.append(contentsOf: [
                xdgConfigHome.appendingPathComponent("claude"),
                homeDirectory.appendingPathComponent(".claude"),
            ])
        }

        return
            directories
            .filter { isDirectory($0.appendingPathComponent("projects")) }
            .uniquedByPath()
    }

    func normalizeClaudeConfigPath(_ url: URL) -> URL {
        if url.lastPathComponent == "projects", isDirectory(url) {
            return url.deletingLastPathComponent().standardizedFileURL
        }
        return url.standardizedFileURL
    }

    func readClaudeUsageFile(_ file: URL) -> [ClaudeUsageEntry] {
        var entries: [ClaudeUsageEntry] = []
        let usageNeedle = Data(#""usage""#.utf8)

        forEachJSONLine(in: file) { line in
            guard line.range(of: usageNeedle) != nil,
                let object = parseJSONObject(line),
                let entry = claudeUsageEntry(from: object)
            else {
                return
            }
            entries.append(entry)
        }

        return entries
    }

    func claudeUsageEntry(from object: JSONObject) -> ClaudeUsageEntry? {
        if let message = dictionary(object["message"]) {
            return claudeUsageEntry(
                timestampValue: object["timestamp"],
                message: message,
                requestIDValue: object["requestId"],
                isSidechainValue: object["isSidechain"]
            )
        }

        guard let data = dictionary(object["data"]),
            let outerMessage = dictionary(data["message"]),
            let message = dictionary(outerMessage["message"])
        else {
            return nil
        }

        return claudeUsageEntry(
            timestampValue: outerMessage["timestamp"],
            message: message,
            requestIDValue: outerMessage["requestId"],
            isSidechainValue: outerMessage["isSidechain"]
        )
    }

    func claudeUsageEntry(
        timestampValue: Any?,
        message: JSONObject,
        requestIDValue: Any?,
        isSidechainValue: Any?
    ) -> ClaudeUsageEntry? {
        guard let timestamp = parseTimestamp(timestampValue),
            let usage = dictionary(message["usage"])
        else {
            return nil
        }

        let inputTokens = unsignedInteger(usage["input_tokens"]) ?? 0
        let outputTokens = unsignedInteger(usage["output_tokens"]) ?? 0
        let cacheCreationTokens = claudeCacheCreationTokens(from: usage)
        let cacheReadTokens = unsignedInteger(usage["cache_read_input_tokens"]) ?? 0
        let speed = string(usage["speed"])

        return ClaudeUsageEntry(
            timestamp: timestamp,
            counts: .claude(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens.ephemeral5m
                    + cacheCreationTokens.ephemeral1h,
                cacheReadTokens: cacheReadTokens,
                costUSD: CodingUsagePricing.claudeCost(
                    model: string(message["model"]),
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheCreation5mTokens: cacheCreationTokens.ephemeral5m,
                    cacheCreation1hTokens: cacheCreationTokens.ephemeral1h,
                    cacheReadTokens: cacheReadTokens,
                    usesFastPricing: speed == "fast"
                )
            ),
            messageID: string(message["id"]),
            requestID: string(requestIDValue),
            isSidechain: bool(isSidechainValue) == true
        )
    }

    func claudeCacheCreationTokens(from usage: JSONObject) -> (
        ephemeral5m: UInt64, ephemeral1h: UInt64
    ) {
        if let cacheCreation = dictionary(usage["cache_creation"]) {
            return (
                ephemeral5m: unsignedInteger(cacheCreation["ephemeral_5m_input_tokens"]) ?? 0,
                ephemeral1h: unsignedInteger(cacheCreation["ephemeral_1h_input_tokens"]) ?? 0
            )
        }
        return (
            ephemeral5m: unsignedInteger(usage["cache_creation_input_tokens"]) ?? 0, ephemeral1h: 0
        )
    }

    func dedupeClaudeEntries(_ entries: [ClaudeUsageEntry]) -> [ClaudeUsageEntry] {
        var indexesByExactKey: [ClaudeDedupeKey: Int] = [:]
        var indexesByMessageID: [String: Int] = [:]
        var deduped: [ClaudeUsageEntry] = []

        for entry in entries {
            guard let messageID = entry.messageID else {
                deduped.append(entry)
                continue
            }

            // A reply is logged twice: once on the main chain and once as a sidechain
            // summary sharing the same message id. Match the exact (message, request)
            // pair, and also collapse same-message entries when either is a sidechain.
            let exactKey = ClaudeDedupeKey(messageID: messageID, requestID: entry.requestID)
            let existingIndex =
                indexesByExactKey[exactKey]
                ?? indexesByMessageID[messageID].flatMap {
                    entry.isSidechain || deduped[$0].isSidechain ? $0 : nil
                }

            if let existingIndex {
                if shouldReplaceClaudeEntry(entry, existing: deduped[existingIndex]) {
                    deduped[existingIndex] = entry
                    indexesByExactKey[exactKey] = existingIndex
                    indexesByMessageID[messageID] = existingIndex
                }
                continue
            }

            let index = deduped.count
            deduped.append(entry)
            indexesByExactKey[exactKey] = index
            indexesByMessageID[messageID] = index
        }

        return deduped
    }

    func shouldReplaceClaudeEntry(_ candidate: ClaudeUsageEntry, existing: ClaudeUsageEntry)
        -> Bool
    {
        if candidate.isSidechain != existing.isSidechain {
            return existing.isSidechain
        }
        if candidate.counts.totalTokens != existing.counts.totalTokens {
            return candidate.counts.totalTokens > existing.counts.totalTokens
        }
        return candidate.counts.costUSD > existing.counts.costUSD
    }
}
