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

/// Scalar fields pulled from a Claude `message` object. The cache-creation split
/// prefers the `cache_creation` object's ephemeral buckets and falls back to the flat
/// `cache_creation_input_tokens` count, matching the original loader.
private struct ClaudeMessageFields {
    var id: String?
    var model: String?
    var hasUsage = false
    var input: UInt64 = 0
    var output: UInt64 = 0
    var cacheRead: UInt64 = 0
    var cacheCreationFallback: UInt64 = 0
    var cacheCreation5m: UInt64 = 0
    var cacheCreation1h: UInt64 = 0
    var hasCacheCreationObject = false
    var usesFastPricing = false

    var cacheCreation5mResolved: UInt64 {
        hasCacheCreationObject ? cacheCreation5m : cacheCreationFallback
    }
    var cacheCreation1hResolved: UInt64 {
        hasCacheCreationObject ? cacheCreation1h : 0
    }
}

/// Timestamp, request id, sidechain flag, and message of one log record. The same
/// shape appears at the top level and nested under `data.message` in exported
/// transcripts, so a single reader serves both.
private struct ClaudeRecordFields {
    var timestamp: Date?
    var requestID: String?
    var isSidechain = false
    var message: ClaudeMessageFields?

    mutating func consume(key: JSONKey, from scanner: inout JSONScanner) -> Bool {
        if key == "timestamp" {
            timestamp = scanner.readTimestamp()
        } else if key == "requestId" {
            requestID = scanner.readString()
        } else if key == "isSidechain" {
            isSidechain = scanner.readBool() == true
        } else if key == "message" {
            message = claudeMessageFields(&scanner)
        } else {
            return false
        }
        return true
    }
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
        let directories = configuredDirectories(
            environmentKey: "CLAUDE_CONFIG_DIR",
            defaults: {
                let xdgConfigHome =
                    environment["XDG_CONFIG_HOME"].map { expandHomePath($0) }
                    ?? homeDirectory.appendingPathComponent(".config")

                return [
                    xdgConfigHome.appendingPathComponent("claude"),
                    homeDirectory.appendingPathComponent(".claude"),
                ]
            },
            normalize: normalizeClaudeConfigPath
        )

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
        let usageNeedle = [UInt8](#""usage""#.utf8)

        forEachJSONLine(in: file) { line in
            guard line.contains(usageNeedle) else {
                return
            }
            if let entry = claudeUsageEntry(line) {
                entries.append(entry)
            }
        }

        return entries
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

/// Extracts one Claude entry, accepting both the top-level record and the
/// `data.message` wrapper. The wrapper's record wins only when the top level carries
/// no usage.
private func claudeUsageEntry(_ buffer: UnsafeRawBufferPointer) -> ClaudeUsageEntry? {
    guard var scanner = JSONScanner(buffer), scanner.beginObject() else {
        return nil
    }
    var record = ClaudeRecordFields()
    var wrapped: ClaudeRecordFields?
    while let key = scanner.nextKey() {
        if record.consume(key: key, from: &scanner) {
            continue
        }
        if key == "data" {
            wrapped = claudeWrappedRecord(&scanner)
        } else {
            scanner.skipValue()
        }
    }
    return claudeEntry(from: record) ?? wrapped.flatMap(claudeEntry)
}

/// Reads the `data` object and returns its `message` record.
private func claudeWrappedRecord(_ scanner: inout JSONScanner) -> ClaudeRecordFields? {
    guard scanner.beginObject() else { return nil }
    var record: ClaudeRecordFields?
    while let key = scanner.nextKey() {
        if key == "message" {
            record = claudeRecordFields(&scanner)
        } else {
            scanner.skipValue()
        }
    }
    return record
}

private func claudeRecordFields(_ scanner: inout JSONScanner) -> ClaudeRecordFields {
    var record = ClaudeRecordFields()
    guard scanner.beginObject() else { return record }
    while let key = scanner.nextKey() {
        if !record.consume(key: key, from: &scanner) {
            scanner.skipValue()
        }
    }
    return record
}

private func claudeMessageFields(_ scanner: inout JSONScanner) -> ClaudeMessageFields? {
    guard scanner.beginObject() else { return nil }
    var fields = ClaudeMessageFields()
    while let key = scanner.nextKey() {
        if key == "id" {
            fields.id = scanner.readString()
        } else if key == "model" {
            fields.model = scanner.readString()
        } else if key == "usage" {
            if scanner.beginObject() {
                fields.hasUsage = true
                claudeUsageFields(&scanner, into: &fields)
            }
        } else {
            scanner.skipValue()
        }
    }
    return fields
}

private func claudeUsageFields(_ scanner: inout JSONScanner, into fields: inout ClaudeMessageFields)
{
    while let key = scanner.nextKey() {
        if key == "input_tokens" {
            fields.input = scanner.readUInt64() ?? 0
        } else if key == "output_tokens" {
            fields.output = scanner.readUInt64() ?? 0
        } else if key == "cache_read_input_tokens" {
            fields.cacheRead = scanner.readUInt64() ?? 0
        } else if key == "cache_creation_input_tokens" {
            fields.cacheCreationFallback = scanner.readUInt64() ?? 0
        } else if key == "cache_creation" {
            if scanner.beginObject() {
                fields.hasCacheCreationObject = true
                while let inner = scanner.nextKey() {
                    if inner == "ephemeral_5m_input_tokens" {
                        fields.cacheCreation5m = scanner.readUInt64() ?? 0
                    } else if inner == "ephemeral_1h_input_tokens" {
                        fields.cacheCreation1h = scanner.readUInt64() ?? 0
                    } else {
                        scanner.skipValue()
                    }
                }
            }
        } else if key == "speed" {
            fields.usesFastPricing = scanner.readStringEquals("fast")
        } else {
            scanner.skipValue()
        }
    }
}

private func claudeEntry(from record: ClaudeRecordFields) -> ClaudeUsageEntry? {
    guard let timestamp = record.timestamp, let message = record.message, message.hasUsage else {
        return nil
    }
    let cacheCreation5m = message.cacheCreation5mResolved
    let cacheCreation1h = message.cacheCreation1hResolved
    return ClaudeUsageEntry(
        timestamp: timestamp,
        counts: .claude(
            inputTokens: message.input,
            outputTokens: message.output,
            cacheCreationTokens: cacheCreation5m + cacheCreation1h,
            cacheReadTokens: message.cacheRead,
            costUSD: CodingUsagePricing.cachedCost(
                model: message.model,
                inputTokens: message.input,
                outputTokens: message.output,
                cacheCreation5mTokens: cacheCreation5m,
                cacheCreation1hTokens: cacheCreation1h,
                cacheReadTokens: message.cacheRead,
                usesFastPricing: message.usesFastPricing
            )
        ),
        messageID: message.id,
        requestID: record.requestID,
        isSidechain: record.isSidechain
    )
}
