import Foundation

extension CodingUsageLoader {
    func loadPiUsage(
        files: [URL],
        into accumulator: inout CodingUsageAccumulator
    ) {
        let needles = [JSONLineNeedle(#""usage""#), JSONLineNeedle(#""message""#)]
        for file in files {
            for record in usageRecords(in: file, needles: needles, parse: piUsageRecord) {
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

}

private func piUsageRecord(_ buffer: UnsafeRawBufferPointer)
    -> (timestamp: Date, counts: CodingTokenCounts)?
{
    guard var scanner = JSONScanner(buffer), scanner.beginObject() else {
        return nil
    }

    var timestamp: Date?
    var fields = PiMessageFields()

    while let key = scanner.nextKey() {
        if key == "timestamp" {
            timestamp = scanner.readTimestamp()
        } else if key == "message" {
            fields = piMessageFields(&scanner)
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
    let outputTokens =
        fields.rawOutput == 0
        ? fields.totalTokens.saturatingSubtract(nonOutputTokens) : fields.rawOutput
    let totalTokens = max(fields.totalTokens, nonOutputTokens.saturatingAdd(outputTokens))

    guard totalTokens > 0 else {
        return nil
    }

    let cacheWrite1h = min(fields.cacheWrite1h, fields.cacheWrite)
    let cacheWrite5m = fields.cacheWrite - cacheWrite1h
    let model = fields.model
    return (
        timestamp,
        CodingTokenCounts(
            inputTokens: fields.input,
            outputTokens: outputTokens,
            cacheCreationTokens: fields.cacheWrite,
            cacheReadTokens: fields.cacheRead,
            totalTokens: totalTokens,
            costUSD: CodingUsagePricing.cost(
                model: model,
                tokens: CodingUsageBillableTokens(
                    input: fields.input,
                    output: outputTokens,
                    cacheCreation5m: cacheWrite5m,
                    cacheCreation1h: cacheWrite1h,
                    cacheRead: fields.cacheRead
                )
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
    var rawOutput: UInt64 = 0
    var cacheWrite: UInt64 = 0
    var cacheWrite1h: UInt64 = 0
    var cacheRead: UInt64 = 0
    var totalTokens: UInt64 = 0
}
