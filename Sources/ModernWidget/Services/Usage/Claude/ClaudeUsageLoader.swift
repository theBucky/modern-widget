import Foundation

struct ClaudeUsageScan: Sendable {
    let isInstalled: Bool
    let files: [CodingUsageFile]
}

private struct ClaudeUsageEntry: Sendable {
    let event: CodingUsageEvent
    let messageIDHash: UInt64?
    let requestIDHash: UInt64?
    let isSidechain: Bool
}

private struct ClaudeDedupeKey: Hashable {
    let messageIDHash: UInt64
    let requestIDHash: UInt64?
}

private struct ClaudeMessageFields {
    var idHash: UInt64?
    var model: String?
    var hasUsage = false
    var inputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var cacheReadTokens: UInt64 = 0
    var flatCacheWriteTokens: UInt64 = 0
    var cacheWrite5mTokens: UInt64 = 0
    var cacheWrite1hTokens: UInt64 = 0
    var hasStructuredCacheWrites = false
    var usesUSDataResidency = false

    var resolvedCacheWrite5mTokens: UInt64 {
        hasStructuredCacheWrites ? cacheWrite5mTokens : flatCacheWriteTokens
    }

    var resolvedCacheWrite1hTokens: UInt64 {
        hasStructuredCacheWrites ? cacheWrite1hTokens : 0
    }
}

struct ClaudeUsageLoader: Sendable {
    private let fileSystem: CodingUsageFileSystem
    private let cache = CodingUsageFileCache<ClaudeUsageEntry>()

    init(fileSystem: CodingUsageFileSystem) {
        self.fileSystem = fileSystem
    }

    func isInstalled() -> Bool {
        !configDirectories().isEmpty
    }

    func scan(scope: CodingUsageDateScope, enabled: Bool) -> ClaudeUsageScan {
        let directories = configDirectories()
        let projectDirectories = directories.map { $0.appendingPathComponent("projects") }
        let files =
            enabled
            ? fileSystem.usageFiles(
                in: projectDirectories,
                modifiedSince: scope.history.start
            )
            : []
        return ClaudeUsageScan(isInstalled: !directories.isEmpty, files: files)
    }

    func load(
        _ scan: ClaudeUsageScan,
        scope: CodingUsageDateScope,
        visit: (CodingUsageEvent) -> Void
    ) {
        let cachedEntries = cache.snapshot()
        let entriesByFile = concurrentMap(scan.files) { file in
            if let cached = cachedEntries[file] {
                return cached
            }

            var pricing = ClaudeUsagePricing.Resolver()
            let usageNeedle = JSONLineNeedle(#""usage""#)
            var entries: [ClaudeUsageEntry] = []
            forEachJSONLine(in: file) { line in
                guard line.contains(usageNeedle),
                    let entry = parseEntry(line, pricing: &pricing)
                else {
                    return
                }
                entries.append(entry)
            }
            return entries
        }

        cache.replace(
            with: Dictionary(uniqueKeysWithValues: zip(scan.files, entriesByFile))
        )

        let inScope = entriesByFile.joined().lazy.filter {
            scope.historyDayIndex(containing: $0.event.timestamp) != nil
        }
        for entry in deduplicate(inScope) {
            visit(entry.event)
        }
    }

    private func configDirectories() -> [URL] {
        let directories = fileSystem.configuredDirectories(
            environmentKey: "CLAUDE_CONFIG_DIR",
            defaults: {
                let xdgConfigHome =
                    fileSystem.environment["XDG_CONFIG_HOME"].map(fileSystem.expandHomePath)
                    ?? fileSystem.homeDirectory.appendingPathComponent(".config")
                return [
                    xdgConfigHome.appendingPathComponent("claude"),
                    fileSystem.homeDirectory.appendingPathComponent(".claude"),
                ]
            },
            normalize: normalizeConfigPath
        )
        return directories.filter {
            fileSystem.isDirectory($0.appendingPathComponent("projects"))
        }
    }

    private func normalizeConfigPath(_ url: URL) -> URL {
        if url.lastPathComponent == "projects", fileSystem.isDirectory(url) {
            return url.deletingLastPathComponent().standardizedFileURL
        }
        return url.standardizedFileURL
    }

    private func deduplicate<Entries: Sequence>(_ entries: Entries) -> [ClaudeUsageEntry]
    where Entries.Element == ClaudeUsageEntry {
        var indexesByExactKey: [ClaudeDedupeKey: Int] = [:]
        var indexesByMessageIDHash: [UInt64: Int] = [:]
        var result: [ClaudeUsageEntry] = []

        for entry in entries {
            guard let messageIDHash = entry.messageIDHash else {
                result.append(entry)
                continue
            }

            let exactKey = ClaudeDedupeKey(
                messageIDHash: messageIDHash,
                requestIDHash: entry.requestIDHash
            )
            let existingIndex =
                indexesByExactKey[exactKey]
                ?? indexesByMessageIDHash[messageIDHash].flatMap {
                    entry.isSidechain || result[$0].isSidechain ? $0 : nil
                }

            if let existingIndex {
                if shouldReplace(entry, existing: result[existingIndex]) {
                    result[existingIndex] = entry
                    indexesByExactKey[exactKey] = existingIndex
                    indexesByMessageIDHash[messageIDHash] = existingIndex
                }
                continue
            }

            let index = result.count
            result.append(entry)
            indexesByExactKey[exactKey] = index
            indexesByMessageIDHash[messageIDHash] = index
        }

        return result
    }

    private func shouldReplace(_ candidate: ClaudeUsageEntry, existing: ClaudeUsageEntry) -> Bool {
        if candidate.isSidechain != existing.isSidechain {
            return existing.isSidechain
        }
        if candidate.event.totals.totalTokens != existing.event.totals.totalTokens {
            return candidate.event.totals.totalTokens > existing.event.totals.totalTokens
        }
        return candidate.event.totals.costUSD > existing.event.totals.costUSD
    }
}

private func parseEntry(
    _ buffer: UnsafeRawBufferPointer,
    pricing: inout ClaudeUsagePricing.Resolver
) -> ClaudeUsageEntry? {
    guard var scanner = JSONScanner(buffer), scanner.beginObject() else {
        return nil
    }

    var timestamp: Date?
    var requestIDHash: UInt64?
    var isSidechain = false
    var message: ClaudeMessageFields?
    while let key = scanner.nextKey() {
        if key == "timestamp" {
            timestamp = scanner.readTimestamp()
        } else if key == "requestId" {
            requestIDHash = scanner.readStringValue()?.fnv1a64
        } else if key == "isSidechain" {
            isSidechain = scanner.readBool() == true
        } else if key == "message" {
            message = parseMessage(&scanner)
        } else {
            scanner.skipValue()
        }
    }

    guard let timestamp, let message, message.hasUsage else {
        return nil
    }

    let usage = ClaudeBillableUsage(
        inputTokens: message.inputTokens,
        outputTokens: message.outputTokens,
        cacheWrite5mTokens: message.resolvedCacheWrite5mTokens,
        cacheWrite1hTokens: message.resolvedCacheWrite1hTokens,
        cacheReadTokens: message.cacheReadTokens,
        usesUSDataResidency: message.usesUSDataResidency
    )
    guard let totals = pricing.totals(model: message.model, usage: usage) else {
        return nil
    }

    return ClaudeUsageEntry(
        event: CodingUsageEvent(timestamp: timestamp, totals: totals),
        messageIDHash: message.idHash,
        requestIDHash: requestIDHash,
        isSidechain: isSidechain
    )
}

private func parseMessage(_ scanner: inout JSONScanner) -> ClaudeMessageFields? {
    guard scanner.beginObject() else {
        return nil
    }

    var fields = ClaudeMessageFields()
    while let key = scanner.nextKey() {
        if key == "id" {
            fields.idHash = scanner.readStringValue()?.fnv1a64
        } else if key == "model" {
            fields.model = scanner.readString()
        } else if key == "usage" {
            guard scanner.beginObject() else {
                continue
            }
            fields.hasUsage = true
            parseUsage(&scanner, into: &fields)
        } else {
            scanner.skipValue()
        }
    }
    return fields
}

private func parseUsage(_ scanner: inout JSONScanner, into fields: inout ClaudeMessageFields) {
    while let key = scanner.nextKey() {
        if key == "input_tokens" {
            fields.inputTokens = scanner.readUInt64() ?? 0
        } else if key == "output_tokens" {
            fields.outputTokens = scanner.readUInt64() ?? 0
        } else if key == "cache_read_input_tokens" {
            fields.cacheReadTokens = scanner.readUInt64() ?? 0
        } else if key == "cache_creation_input_tokens" {
            fields.flatCacheWriteTokens = scanner.readUInt64() ?? 0
        } else if key == "cache_creation" {
            parseCacheWrites(&scanner, into: &fields)
        } else if key == "inference_geo" {
            fields.usesUSDataResidency = scanner.readStringEquals("us")
        } else {
            scanner.skipValue()
        }
    }
}

private func parseCacheWrites(
    _ scanner: inout JSONScanner,
    into fields: inout ClaudeMessageFields
) {
    guard scanner.beginObject() else {
        return
    }
    fields.hasStructuredCacheWrites = true
    while let key = scanner.nextKey() {
        if key == "ephemeral_5m_input_tokens" {
            fields.cacheWrite5mTokens = scanner.readUInt64() ?? 0
        } else if key == "ephemeral_1h_input_tokens" {
            fields.cacheWrite1hTokens = scanner.readUInt64() ?? 0
        } else {
            scanner.skipValue()
        }
    }
}
