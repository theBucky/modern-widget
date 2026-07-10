import Foundation

struct CodingUsageFileFingerprint: Hashable, Sendable {
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
            guard file.pathExtension == "jsonl", let fingerprint = usageFileFingerprint(file) else {
                continue
            }
            if let modifiedAt = fingerprint.modifiedAt, modifiedAt < modifiedSince {
                continue
            }
            files.append(CodingUsageFile(url: file, fingerprint: fingerprint))
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
            path: file.path,
            modifiedAt: values?.contentModificationDate,
            byteCount: values?.fileSize
        )
    }

    /// `normalize` must return a standardized URL; the default and every caller do.
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
                .uniqued(by: \.path)

            if !configured.isEmpty {
                return configured
            }
        }

        return defaults().map(normalize).uniqued(by: \.path)
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

extension Sequence {
    /// Keeps the first element for each distinct key, preserving order.
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen: Set<Key> = []
        return filter { seen.insert(key($0)).inserted }
    }
}
