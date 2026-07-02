import Darwin
import Foundation

struct CodingUsageFileFingerprint: Equatable, Sendable {
    let path: String
    let modifiedAt: Date?
    let byteCount: Int?
}

/// A usage log file paired with the fingerprint captured while enumerating it, so
/// change detection never has to stat the file a second time.
struct CodingUsageFile: Sendable {
    let url: URL
    let fingerprint: CodingUsageFileFingerprint
}

extension CodingUsageLoader {
    func usageFiles(in directory: URL, modifiedSince: Date) -> [CodingUsageFile] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
                ]
            )
        else {
            return []
        }

        var files: [CodingUsageFile] = []
        for case let file as URL in enumerator {
            guard file.pathExtension == "jsonl" else {
                continue
            }

            let values = try? file.resourceValues(forKeys: [
                .isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
            ])
            guard values?.isRegularFile == true else {
                continue
            }
            let modifiedAt = values?.contentModificationDate
            if let modifiedAt, modifiedAt < modifiedSince {
                continue
            }
            files.append(
                CodingUsageFile(
                    url: file,
                    fingerprint: CodingUsageFileFingerprint(
                        path: file.standardizedFileURL.path,
                        modifiedAt: modifiedAt,
                        byteCount: values?.fileSize
                    )
                )
            )
        }
        return files.sorted { $0.fingerprint.path < $1.fingerprint.path }
    }

    func usageFileFingerprint(_ file: URL) -> CodingUsageFileFingerprint? {
        let values = try? file.resourceValues(forKeys: [
            .isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
        ])
        guard values?.isRegularFile == true else {
            return nil
        }
        return CodingUsageFileFingerprint(
            path: file.standardizedFileURL.path,
            modifiedAt: values?.contentModificationDate,
            byteCount: values?.fileSize
        )
    }

    func configuredDirectories(
        environmentKey: String,
        defaults: () -> [URL],
        normalize: (URL) -> URL = { $0.standardizedFileURL }
    ) -> [URL] {
        if let rawPaths = environment[environmentKey] {
            let configured =
                rawPaths
                .split(separator: ",")
                .compactMap { token in
                    let path = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    return path.isEmpty ? nil : normalize(expandHomePath(path))
                }
                .uniquedByPath()

            if !configured.isEmpty {
                return configured
            }
        }

        return defaults().map(normalize).uniquedByPath()
    }

    /// Maps `file` and hands each non-empty line to `visit` as a borrowed byte slice of
    /// the mapping. Newlines are located with `memchr` over the raw pointer; slicing the
    /// `Data` per line instead is ~75x slower because every byte pays Collection witness
    /// and bounds-check overhead.
    func forEachJSONLine(
        in file: URL,
        _ visit: (UnsafeRawBufferPointer) -> Void
    ) {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe), !data.isEmpty else {
            return
        }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let count = raw.count
            var start = 0
            while start < count {
                let newline = memchr(bytes + start, 0x0a, count - start)
                let end = newline.map { UnsafeRawPointer($0) - UnsafeRawPointer(bytes) } ?? count
                if end > start {
                    visit(UnsafeRawBufferPointer(start: bytes + start, count: end - start))
                }
                if newline == nil {
                    break
                }
                start = end + 1
            }
        }
    }

    /// Maps `elements` on all cores, preserving order. Usage logs are hundreds of
    /// megabytes across thousands of independent files, and parsing dominates every
    /// reload; one file per core is what keeps a reload interactive.
    func concurrentMap<Element: Sendable, Transformed: Sendable>(
        _ elements: [Element],
        _ transform: @Sendable (Element) -> Transformed
    ) -> [Transformed] {
        Array(unsafeUninitializedCapacity: elements.count) { buffer, initializedCount in
            nonisolated(unsafe) let results = buffer
            DispatchQueue.concurrentPerform(iterations: elements.count) { index in
                results.initializeElement(at: index, to: transform(elements[index]))
            }
            initializedCount = elements.count
        }
    }

    /// Collects whatever `parse` extracts from each line of `file`, skipping lines that
    /// lack any needle so the scanner only descends into candidate lines.
    func usageRecords<Record>(
        in file: URL,
        needles: [JSONLineNeedle],
        parse: (UnsafeRawBufferPointer) -> Record?
    ) -> [Record] {
        var records: [Record] = []
        forEachJSONLine(in: file) { line in
            guard needles.allSatisfy(line.contains) else {
                return
            }
            if let record = parse(line) {
                records.append(record)
            }
        }
        return records
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
}

extension Array where Element == CodingUsageFileFingerprint {
    func uniquedByPath() -> [CodingUsageFileFingerprint] {
        var seen: Set<String> = []
        return filter { seen.insert($0.path).inserted }
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
