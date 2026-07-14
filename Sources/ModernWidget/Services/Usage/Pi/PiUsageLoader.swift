import Foundation

struct PiUsageScan: Sendable {
    let isInstalled: Bool
    let files: [CodingUsageFile]
}

private struct PiMessageFields {
    var isAssistant = false
    var hasUsage = false
    var totalTokens: UInt64?
    var totalCostUSD: Double?
}

struct PiUsageLoader: Sendable {
    private let fileSystem: CodingUsageFileSystem
    private let cache = CodingUsageFileCache<CodingUsageEvent>()

    init(fileSystem: CodingUsageFileSystem) {
        self.fileSystem = fileSystem
    }

    func isInstalled() -> Bool {
        !usageDirectories().isEmpty
    }

    func scan(scope: CodingUsageDateScope, enabled: Bool) -> PiUsageScan {
        let directories = usageDirectories()
        let files =
            enabled
            ? fileSystem.usageFiles(in: directories, modifiedSince: scope.history.start)
            : []
        return PiUsageScan(isInstalled: !directories.isEmpty, files: files)
    }

    func load(_ scan: PiUsageScan, visit: (CodingUsageEvent) -> Void) {
        let cachedRecords = cache.snapshot()
        let recordsByFile = concurrentMap(scan.files) { file in
            if let cached = cachedRecords[file] {
                return cached
            }

            var records: [CodingUsageEvent] = []
            forEachJSONLine(in: file) { line in
                if let event = parsePiEvent(line) {
                    records.append(event)
                }
            }
            return records
        }

        cache.replace(
            with: Dictionary(uniqueKeysWithValues: zip(scan.files, recordsByFile))
        )
        for records in recordsByFile {
            for event in records {
                visit(event)
            }
        }
    }

    private func usageDirectories() -> [URL] {
        fileSystem.configuredDirectories(environmentKey: "PI_AGENT_DIR") {
            [fileSystem.homeDirectory.appendingPathComponent(".pi/agent/sessions")]
        }
        .filter(fileSystem.isDirectory)
    }
}

private func parsePiEvent(_ buffer: UnsafeRawBufferPointer) -> CodingUsageEvent? {
    guard var scanner = JSONScanner(buffer), scanner.beginObject() else {
        return nil
    }

    var isMessage = false
    var timestamp: Date?
    var message: PiMessageFields?
    while let key = scanner.nextKey() {
        if key == "type" {
            isMessage = scanner.readStringEquals("message")
        } else if key == "timestamp" {
            timestamp = scanner.readTimestamp()
        } else if key == "message" {
            message = parsePiMessage(&scanner)
        } else {
            scanner.skipValue()
        }
    }

    guard isMessage, let timestamp, let message,
        message.isAssistant, message.hasUsage,
        let totalTokens = message.totalTokens,
        let totalCostUSD = message.totalCostUSD,
        totalCostUSD >= 0,
        totalTokens > 0 || totalCostUSD > 0
    else {
        return nil
    }

    return CodingUsageEvent(
        timestamp: timestamp,
        totals: CodingUsageTotals(totalTokens: totalTokens, costUSD: totalCostUSD)
    )
}

private func parsePiMessage(_ scanner: inout JSONScanner) -> PiMessageFields? {
    guard scanner.beginObject() else {
        return nil
    }

    var fields = PiMessageFields()
    while let key = scanner.nextKey() {
        if key == "role" {
            fields.isAssistant = scanner.readStringEquals("assistant")
        } else if key == "usage" {
            guard scanner.beginObject() else {
                continue
            }
            fields.hasUsage = true
            parsePiUsage(&scanner, into: &fields)
        } else {
            scanner.skipValue()
        }
    }
    return fields
}

private func parsePiUsage(_ scanner: inout JSONScanner, into fields: inout PiMessageFields) {
    while let key = scanner.nextKey() {
        if key == "totalTokens" {
            fields.totalTokens = scanner.readUInt64()
        } else if key == "cost" {
            fields.totalCostUSD = parsePiCost(&scanner)
        } else {
            scanner.skipValue()
        }
    }
}

private func parsePiCost(_ scanner: inout JSONScanner) -> Double? {
    guard scanner.beginObject() else {
        return nil
    }

    var total: Double?
    while let key = scanner.nextKey() {
        if key == "total" {
            total = scanner.readDouble()
        } else {
            scanner.skipValue()
        }
    }
    return total
}
