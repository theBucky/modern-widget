import Foundation

typealias JSONObject = [String: Any]

extension CodingUsageLoader {
    func usageFiles(
        in directory: URL,
        modifiedSince: Date
    ) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: []
            )
        else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            guard file.pathExtension == "jsonl" else {
                continue
            }

            let values = try? file.resourceValues(forKeys: [
                .contentModificationDateKey, .isRegularFileKey,
            ])
            guard values?.isRegularFile == true
            else {
                continue
            }
            if let modifiedAt = values?.contentModificationDate, modifiedAt < modifiedSince {
                continue
            }
            files.append(file)
        }
        return files.sorted { $0.path < $1.path }
    }

    func forEachJSONLine(
        in file: URL,
        _ visit: (Data) -> Void
    ) {
        let data: Data
        do {
            data = try Data(contentsOf: file, options: .mappedIfSafe)
        } catch {
            return
        }

        guard !data.isEmpty else {
            return
        }

        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: UInt8(ascii: "\n")) ?? data.endIndex
            if start < end {
                visit(data[start..<end])
            }
            if end == data.endIndex {
                break
            }
            start = data.index(after: end)
        }
    }

    func parseJSONObject(_ data: Data) -> JSONObject? {
        (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
    }

    func dictionary(_ value: Any?) -> JSONObject? {
        value as? JSONObject
    }

    func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBooleanNumber(number) else {
            return nil
        }
        return number.boolValue
    }

    func unsignedInteger(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber, !isBooleanNumber(number) else {
            return nil
        }
        return number as? UInt64
    }

    func parseTimestamp(_ value: Any?) -> Date? {
        if let text = string(value) {
            return parseTimestampString(text)
        }

        guard let number = value as? NSNumber, !isBooleanNumber(number) else {
            return nil
        }
        let raw = number.doubleValue
        if raw > 10_000_000_000 {
            return Date(timeIntervalSince1970: raw / 1_000)
        }
        return Date(timeIntervalSince1970: raw)
    }

    func nonEmptyString(_ value: Any?) -> String? {
        string(value).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func parseTimestampString(_ value: String) -> Date? {
        // ISO8601DateFormatter is neither Sendable nor documented thread-safe, so it is
        // built per call rather than shared across concurrent scans.
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) {
            return date
        }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }

    func fileModifiedDate(_ url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    func expandHomePath(_ rawPath: String) -> URL {
        if rawPath == "~" {
            return homeDirectory
        }
        if rawPath.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(rawPath.dropFirst(2)))
        }
        return URL(fileURLWithPath: rawPath)
    }

    func relativePath(_ url: URL, from base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(basePath + "/") {
            return String(path.dropFirst(basePath.count + 1))
        }
        return url.lastPathComponent
    }

    private func isBooleanNumber(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}

extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}

extension Array where Element == URL {
    func uniquedByPath() -> [URL] {
        var seen: Set<String> = []
        var urls: [URL] = []
        for url in self {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                urls.append(url.standardizedFileURL)
            }
        }
        return urls
    }
}
