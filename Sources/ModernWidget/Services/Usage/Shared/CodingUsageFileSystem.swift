import Darwin
import Foundation

struct CodingUsageFileFingerprint: Equatable, Sendable {
    let path: String
    let modifiedAt: Date?
    let byteCount: Int?
}

extension CodingUsageLoader {
    func usageFiles(in directory: URL, modifiedSince: Date) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
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
                .isRegularFileKey, .contentModificationDateKey,
            ])
            guard values?.isRegularFile == true else {
                continue
            }
            if let modifiedAt = values?.contentModificationDate,
                modifiedAt < modifiedSince
            {
                continue
            }
            files.append(file)
        }
        return files.sorted { $0.path < $1.path }
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
