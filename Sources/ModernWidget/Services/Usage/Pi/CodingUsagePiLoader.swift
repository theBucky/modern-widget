import Foundation

struct PiUsageRecord: Sendable {
    let timestamp: Date
    let counts: CodingTokenCounts
}

extension CodingUsageLoader {
    func loadPiUsage(
        files: [CodingUsageFile],
        into accumulator: inout CodingUsageAccumulator
    ) {
        let cachedRecords = parseCache.piRecords()
        let records = concurrentMap(files) { file in
            if let cached = cachedRecords[file.fingerprint] {
                return cached
            }
            var pricing = CodingUsagePricing.Resolver()
            var records: [PiUsageRecord] = []
            forEachJSONLine(in: file) { line in
                if let record = piUsageRecord(line, pricing: &pricing) {
                    records.append(record)
                }
            }
            return records
        }
        var recordsByFingerprint: [CodingUsageFileFingerprint: [PiUsageRecord]] = [:]
        recordsByFingerprint.reserveCapacity(files.count)
        for (file, fileRecords) in zip(files, records) {
            recordsByFingerprint[file.fingerprint] = fileRecords
        }
        parseCache.replacePiRecords(recordsByFingerprint)
        for record in records.joined() {
            accumulator.add(.pi, counts: record.counts, at: record.timestamp)
        }
    }

    func piUsageFiles(in directories: [URL], scope: CodingUsageDateScope) -> [CodingUsageFile] {
        directories.flatMap {
            usageFiles(in: $0, modifiedSince: scope.history.start)
        }
    }

    func piUsageDirectories() -> [URL] {
        configuredDirectories(environmentKey: "PI_AGENT_DIR") {
            [homeDirectory.appendingPathComponent(".pi/agent/sessions")]
        }
        .filter(isDirectory)
    }
}

private func piUsageRecord(
    _ buffer: UnsafeRawBufferPointer,
    pricing: inout CodingUsagePricing.Resolver
) -> PiUsageRecord? {
    guard var scanner = JSONScanner(buffer), scanner.beginObject() else {
        return nil
    }

    var timestamp: Date?
    var fields = PiMessageFields()

    while let key = scanner.nextKey() {
        if key == "type" {
            if !scanner.readStringEquals("message") {
                return nil
            }
        } else if key == "timestamp" {
            timestamp = scanner.readTimestamp()
        } else if key == "message" {
            guard let messageFields = piMessageFields(&scanner) else {
                return nil
            }
            fields = messageFields
        } else {
            scanner.skipValue()
        }
    }

    guard let timestamp, fields.isAssistant, fields.hasUsage else {
        return nil
    }

    let nonOutputTokens =
        fields.input
        .saturatingAdd(fields.cacheWrite)
        .saturatingAdd(fields.cacheRead)
    let outputTokens = fields.output ?? fields.totalTokens.saturatingSubtract(nonOutputTokens)
    let totalTokens = max(fields.totalTokens, nonOutputTokens.saturatingAdd(outputTokens))

    guard totalTokens > 0 else {
        return nil
    }

    let cacheWrite1h = min(fields.cacheWrite1h, fields.cacheWrite)
    let cacheWrite = fields.cacheWrite - cacheWrite1h
    let model = fields.model
    return PiUsageRecord(
        timestamp: timestamp,
        counts: CodingTokenCounts(
            inputTokens: fields.input,
            outputTokens: outputTokens,
            cacheCreationTokens: fields.cacheWrite,
            cacheReadTokens: fields.cacheRead,
            totalTokens: totalTokens,
            costUSD: pricing.cost(
                model: model,
                tokens: CodingUsageBillableTokens(
                    input: fields.input,
                    output: outputTokens,
                    cacheCreation: cacheWrite,
                    cacheCreation1h: cacheWrite1h,
                    cacheRead: fields.cacheRead
                )
            )
        )
    )
}

private func piMessageFields(_ scanner: inout JSONScanner) -> PiMessageFields? {
    var fields = PiMessageFields()
    guard scanner.beginObject() else { return nil }
    while let key = scanner.nextKey() {
        if key == "role" {
            fields.isAssistant = scanner.readStringEquals("assistant")
            if !fields.isAssistant {
                return nil
            }
        } else if key == "model" {
            fields.model = scanner.readString()
        } else if key == "usage" {
            if scanner.beginObject() {
                fields.hasUsage = true
                while let inner = scanner.nextKey() {
                    if inner == "input" {
                        fields.input = scanner.readUInt64() ?? 0
                    } else if inner == "output" {
                        fields.output = scanner.readUInt64()
                    } else if inner == "cacheWrite" {
                        fields.cacheWrite = scanner.readUInt64() ?? 0
                    } else if inner == "cacheRead" {
                        fields.cacheRead = scanner.readUInt64() ?? 0
                    } else if inner == "cacheWrite1h" {
                        fields.cacheWrite1h = scanner.readUInt64() ?? 0
                    } else if inner == "totalTokens" {
                        fields.totalTokens = scanner.readUInt64() ?? 0
                    } else {
                        scanner.skipValue()
                    }
                }
            }
        } else {
            scanner.skipValue()
        }
    }
    return fields
}

private struct PiMessageFields {
    var isAssistant = false
    var model: String?
    var hasUsage = false
    var input: UInt64 = 0
    var output: UInt64?
    var cacheWrite: UInt64 = 0
    var cacheWrite1h: UInt64 = 0
    var cacheRead: UInt64 = 0
    var totalTokens: UInt64 = 0
}
