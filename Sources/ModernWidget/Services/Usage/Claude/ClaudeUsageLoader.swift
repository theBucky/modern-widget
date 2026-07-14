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
    var isAssistant = false
    var idHash: UInt64?
    var model: String?
    var usage: ClaudeUsageFields?
}

private struct ClaudeUsageFields {
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
    private let cache = CodingUsageFileCache<[ClaudeUsageEntry]>()

    init(fileSystem: CodingUsageFileSystem) {
        self.fileSystem = fileSystem
    }

    func isInstalled() -> Bool {
        fileSystem.isDirectory(projectsDirectory)
    }

    func scan(scope: CodingUsageDateScope, enabled: Bool) -> ClaudeUsageScan {
        let isInstalled = fileSystem.isDirectory(projectsDirectory)
        let files =
            enabled && isInstalled
            ? fileSystem.usageFiles(
                in: projectsDirectory,
                modifiedSince: scope.history.start
            )
            : []
        return ClaudeUsageScan(isInstalled: isInstalled, files: files)
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

    private var projectsDirectory: URL {
        fileSystem.homeDirectory.appendingPathComponent(".claude/projects")
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

    guard scanner.finishDocument(), let timestamp, let message,
        message.isAssistant, let fields = message.usage
    else {
        return nil
    }

    let usage = ClaudeBillableUsage(
        inputTokens: fields.inputTokens,
        outputTokens: fields.outputTokens,
        cacheWrite5mTokens: fields.resolvedCacheWrite5mTokens,
        cacheWrite1hTokens: fields.resolvedCacheWrite1hTokens,
        cacheReadTokens: fields.cacheReadTokens,
        usesUSDataResidency: fields.usesUSDataResidency
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
        if key == "role" {
            fields.isAssistant = scanner.readStringEquals("assistant")
        } else if key == "id" {
            fields.idHash = scanner.readStringValue()?.fnv1a64
        } else if key == "model" {
            fields.model = scanner.readString()
        } else if key == "usage" {
            fields.usage = parseUsage(&scanner)
        } else {
            scanner.skipValue()
        }
    }
    return fields
}

private func parseUsage(_ scanner: inout JSONScanner) -> ClaudeUsageFields? {
    guard scanner.beginObject() else {
        return nil
    }

    var fields = ClaudeUsageFields()
    var isValid = true
    while let key = scanner.nextKey() {
        if key == "input_tokens" {
            fields.inputTokens = readTokenCount(&scanner, isValid: &isValid)
        } else if key == "output_tokens" {
            fields.outputTokens = readTokenCount(&scanner, isValid: &isValid)
        } else if key == "cache_read_input_tokens" {
            fields.cacheReadTokens = readTokenCount(&scanner, isValid: &isValid)
        } else if key == "cache_creation_input_tokens" {
            fields.flatCacheWriteTokens = readTokenCount(&scanner, isValid: &isValid)
        } else if key == "cache_creation" {
            isValid = parseCacheWrites(&scanner, into: &fields) && isValid
        } else if key == "inference_geo" {
            fields.usesUSDataResidency = scanner.readStringEquals("us")
        } else {
            scanner.skipValue()
        }
    }
    return isValid ? fields : nil
}

private func parseCacheWrites(
    _ scanner: inout JSONScanner,
    into fields: inout ClaudeUsageFields
) -> Bool {
    guard scanner.beginObject() else {
        return false
    }
    fields.hasStructuredCacheWrites = true
    var isValid = true
    while let key = scanner.nextKey() {
        if key == "ephemeral_5m_input_tokens" {
            fields.cacheWrite5mTokens = readTokenCount(&scanner, isValid: &isValid)
        } else if key == "ephemeral_1h_input_tokens" {
            fields.cacheWrite1hTokens = readTokenCount(&scanner, isValid: &isValid)
        } else {
            scanner.skipValue()
        }
    }
    return isValid
}

private func readTokenCount(_ scanner: inout JSONScanner, isValid: inout Bool) -> UInt64 {
    guard let value = scanner.readUInt64() else {
        isValid = false
        return 0
    }
    return value
}
