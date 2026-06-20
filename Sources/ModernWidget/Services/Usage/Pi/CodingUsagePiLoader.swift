import Foundation

extension CodingUsageLoader {
    func loadPiUsage(
        files: [URL],
        into accumulator: inout CodingUsageAccumulator
    ) {
        for file in files {
            for record in readPiUsageFile(file) {
                accumulator.add(.pi, counts: record.counts, at: record.timestamp)
            }
        }
    }

    func piUsageFiles(scope: CodingUsageDateScope) -> [URL] {
        piUsageDirectories().flatMap {
            usageFiles(in: $0, modifiedSince: scope.history.start)
        }
    }

    func piUsageDirectories() -> [URL] {
        configuredDirectories(environmentKey: "PI_AGENT_DIR") {
            [homeDirectory.appendingPathComponent(".pi/agent/sessions")]
        }
        .filter(isDirectory)
    }

    func readPiUsageFile(_ file: URL) -> [(timestamp: Date, counts: CodingTokenCounts)] {
        let usageNeedle = JSONLineNeedle(#""usage""#)
        let messageNeedle = JSONLineNeedle(#""message""#)
        var records: [(timestamp: Date, counts: CodingTokenCounts)] = []

        forEachJSONLine(in: file) { line in
            guard line.contains(usageNeedle), line.contains(messageNeedle) else {
                return
            }
            if let record = piUsageRecord(line) {
                records.append(record)
            }
        }

        return records
    }
}

private func piUsageRecord(_ buffer: UnsafeRawBufferPointer)
    -> (timestamp: Date, counts: CodingTokenCounts)?
{
    guard var scanner = JSONScanner(buffer), scanner.beginObject() else {
        return nil
    }

    var isMessage = true
    var timestamp: Date?
    var fields = PiMessageFields()

    while let key = scanner.nextKey() {
        if key == "type" {
            isMessage = scanner.readStringEquals("message")
        } else if key == "timestamp" {
            timestamp = scanner.readTimestamp()
        } else if key == "message" {
            fields = piMessageFields(&scanner)
        } else {
            scanner.skipValue()
        }
    }

    guard isMessage, let timestamp, fields.isAssistant, fields.hasUsage else {
        return nil
    }

    let knownTokens = fields.input + fields.rawOutput + fields.cacheWrite + fields.cacheRead
    let outputTokens =
        fields.rawOutput == 0
        ? fields.totalTokens.saturatingSubtract(knownTokens) : fields.rawOutput
    let totalTokens = max(
        fields.totalTokens,
        fields.input + outputTokens + fields.cacheWrite + fields.cacheRead
    )

    guard totalTokens > 0 else {
        return nil
    }

    let model = fields.model?.nilIfEmpty
    return (
        timestamp,
        CodingTokenCounts(
            inputTokens: fields.input,
            outputTokens: outputTokens,
            cacheCreationTokens: fields.cacheWrite,
            cacheReadTokens: fields.cacheRead,
            totalTokens: totalTokens,
            costUSD: CodingUsagePricing.cachedCost(
                model: model,
                inputTokens: fields.input,
                outputTokens: outputTokens,
                cacheCreation5mTokens: fields.cacheWrite,
                cacheReadTokens: fields.cacheRead
            )
        )
    )
}

private func piMessageFields(_ scanner: inout JSONScanner) -> PiMessageFields {
    var fields = PiMessageFields()
    guard scanner.beginObject() else { return fields }
    while let key = scanner.nextKey() {
        if key == "role" {
            fields.isAssistant = scanner.readStringEquals("assistant")
        } else if key == "model" {
            fields.model = scanner.readString()
        } else if key == "usage" {
            if scanner.beginObject() {
                fields.hasUsage = true
                while let inner = scanner.nextKey() {
                    if inner == "input" {
                        fields.input = scanner.readUInt64() ?? 0
                    } else if inner == "output" {
                        fields.rawOutput = scanner.readUInt64() ?? 0
                    } else if inner == "cacheWrite" {
                        fields.cacheWrite = scanner.readUInt64() ?? 0
                    } else if inner == "cacheRead" {
                        fields.cacheRead = scanner.readUInt64() ?? 0
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
    var rawOutput: UInt64 = 0
    var cacheWrite: UInt64 = 0
    var cacheRead: UInt64 = 0
    var totalTokens: UInt64 = 0
}
