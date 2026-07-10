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

/// Scalar fields pulled from a Claude `message` object. Cache creation prefers the
/// `cache_creation` object's ephemeral buckets; the flat `cache_creation_input_tokens`
/// fallback counts only as 5 minute cache creation, never 1 hour.
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

extension CodingUsageLoader {
    func loadClaudeUsage(
        files: [CodingUsageFile],
        scope: CodingUsageDateScope,
        into accumulator: inout CodingUsageAccumulator
    ) {
        // Files parse in parallel; the date filter stays ahead of the dedupe below so an
        // out-of-window duplicate can never beat an in-window record.
        let cachedRecords = parseCache.claudeRecords()
        let entries = concurrentMap(files) { file in
            if let cached = cachedRecords[file.fingerprint] {
                return cached
            }
            var pricing = CodingUsagePricing.Resolver()
            let usageNeedle = JSONLineNeedle(#""usage""#)
            var records: [ClaudeUsageEntry] = []
            forEachJSONLine(in: file) { line in
                guard line.contains(usageNeedle),
                    let entry = claudeUsageEntry(line, pricing: &pricing)
                else {
                    return
                }
                records.append(entry)
            }
            return records
        }
        var recordsByFingerprint: [CodingUsageFileFingerprint: [ClaudeUsageEntry]] = [:]
        recordsByFingerprint.reserveCapacity(files.count)
        for (file, records) in zip(files, entries) {
            recordsByFingerprint[file.fingerprint] = records
        }
        parseCache.replaceClaudeRecords(recordsByFingerprint)

        let inScope = entries.joined().lazy.filter {
            scope.historyDay(containing: $0.timestamp) != nil
        }
        for entry in dedupeClaudeEntries(inScope) {
            accumulator.add(.claude, counts: entry.counts, at: entry.timestamp)
        }
    }

    func claudeUsageFiles(in directories: [URL], scope: CodingUsageDateScope) -> [CodingUsageFile] {
        directories.flatMap {
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

        return directories.filter { isDirectory($0.appendingPathComponent("projects")) }
    }

    func normalizeClaudeConfigPath(_ url: URL) -> URL {
        if url.lastPathComponent == "projects", isDirectory(url) {
            return url.deletingLastPathComponent().standardizedFileURL
        }
        return url.standardizedFileURL
    }

    func dedupeClaudeEntries<Entries: Sequence>(_ entries: Entries) -> [ClaudeUsageEntry]
    where Entries.Element == ClaudeUsageEntry {
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

/// Extracts one Claude entry from a top-level `~/.claude/projects` transcript record.
private func claudeUsageEntry(
    _ buffer: UnsafeRawBufferPointer,
    pricing: inout CodingUsagePricing.Resolver
) -> ClaudeUsageEntry? {
    guard var scanner = JSONScanner(buffer), scanner.beginObject() else {
        return nil
    }
    var timestamp: Date?
    var requestID: String?
    var isSidechain = false
    var message: ClaudeMessageFields?
    var sawRequestID = false
    var sawIsSidechain = false
    while let key = scanner.nextKey() {
        if key == "timestamp" {
            timestamp = scanner.readTimestamp()
        } else if key == "requestId" {
            requestID = scanner.readString()
            sawRequestID = true
        } else if key == "isSidechain" {
            isSidechain = scanner.readBool() == true
            sawIsSidechain = true
        } else if key == "message" {
            message = claudeMessageFields(&scanner)
        } else {
            scanner.skipValue()
        }
        if timestamp != nil, message != nil, sawRequestID, sawIsSidechain {
            break
        }
    }

    guard let timestamp, let message, message.hasUsage else {
        return nil
    }
    let cacheCreation5m = message.cacheCreation5mResolved
    let cacheCreation1h = message.cacheCreation1hResolved
    let cacheCreationTokens = cacheCreation5m.saturatingAdd(cacheCreation1h)
    let totalTokens =
        message.input
        .saturatingAdd(message.output)
        .saturatingAdd(cacheCreationTokens)
        .saturatingAdd(message.cacheRead)
    return ClaudeUsageEntry(
        timestamp: timestamp,
        counts: CodingTokenCounts(
            inputTokens: message.input,
            outputTokens: message.output,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: message.cacheRead,
            totalTokens: totalTokens,
            costUSD: pricing.cost(
                model: message.model,
                tokens: CodingUsageBillableTokens(
                    input: message.input,
                    output: message.output,
                    cacheCreation: cacheCreation5m,
                    cacheCreation1h: cacheCreation1h,
                    cacheRead: message.cacheRead,
                    usesFastPricing: message.usesFastPricing
                )
            )
        ),
        messageID: message.id,
        requestID: requestID,
        isSidechain: isSidechain
    )
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
