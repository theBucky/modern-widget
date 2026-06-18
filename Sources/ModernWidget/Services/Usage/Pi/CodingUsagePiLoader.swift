import Foundation

extension CodingUsageLoader {
    func loadPiUsage(
        scope: CodingUsageDateScope,
        into accumulator: inout CodingUsageAccumulator
    ) {
        for directory in piUsageDirectories() {
            for file in usageFiles(in: directory) {
                for record in readPiUsageFile(file) {
                    accumulator.add(.pi, counts: record.counts, at: record.timestamp)
                }
            }
        }
    }

    func piUsageDirectories() -> [URL] {
        if let rawPaths = environment["PI_AGENT_DIR"],
            !rawPaths.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return
                rawPaths
                .split(separator: ",")
                .map { expandHomePath(String($0).trimmingCharacters(in: .whitespaces)) }
                .filter(isDirectory)
                .uniquedByPath()
        }

        let sessions = homeDirectory.appendingPathComponent(".pi/agent/sessions")
        return isDirectory(sessions) ? [sessions.standardizedFileURL] : []
    }

    func readPiUsageFile(_ file: URL) -> [(timestamp: Date, counts: CodingTokenCounts)] {
        let usageNeedle = Data(#""usage""#.utf8)
        let messageNeedle = Data(#""message""#.utf8)
        var records: [(timestamp: Date, counts: CodingTokenCounts)] = []

        forEachJSONLine(in: file) { line in
            guard line.range(of: usageNeedle) != nil,
                line.range(of: messageNeedle) != nil,
                let object = parseJSONObject(line),
                let record = piUsageRecord(from: object)
            else {
                return
            }
            records.append(record)
        }

        return records
    }

    func piUsageRecord(from object: JSONObject) -> (timestamp: Date, counts: CodingTokenCounts)? {
        if let messageType = string(object["type"]), messageType != "message" {
            return nil
        }
        guard let timestamp = parseTimestamp(object["timestamp"]),
            let message = dictionary(object["message"]),
            string(message["role"]) == "assistant",
            let usage = dictionary(message["usage"])
        else {
            return nil
        }

        let inputTokens = unsignedInteger(usage["input"]) ?? 0
        let rawOutputTokens = unsignedInteger(usage["output"]) ?? 0
        let cacheCreationTokens = unsignedInteger(usage["cacheWrite"]) ?? 0
        let cacheReadTokens = unsignedInteger(usage["cacheRead"]) ?? 0
        let reportedTotalTokens = unsignedInteger(usage["totalTokens"]) ?? 0
        let knownTokens = inputTokens + rawOutputTokens + cacheCreationTokens + cacheReadTokens
        let outputTokens =
            rawOutputTokens == 0
            ? reportedTotalTokens.saturatingSubtract(knownTokens) : rawOutputTokens
        let totalTokens = max(
            reportedTotalTokens,
            inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
        )

        guard totalTokens > 0 else {
            return nil
        }

        let model = nonEmptyString(message["model"])
        return (
            timestamp,
            CodingTokenCounts(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens,
                totalTokens: totalTokens,
                costUSD: CodingUsagePricing.cachedTokenCost(
                    model: model,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheCreationTokens: cacheCreationTokens,
                    cacheReadTokens: cacheReadTokens
                )
            )
        )
    }
}
