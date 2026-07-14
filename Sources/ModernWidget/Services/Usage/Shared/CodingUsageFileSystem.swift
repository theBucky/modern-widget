import Darwin
import Foundation

struct CodingUsageFile: Hashable, Sendable {
    let path: String
    let modifiedAt: Date
    let byteCount: Int

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: false)
    }
}

struct CodingUsageFileSystem: Sendable {
    let environment: [String: String]
    let homeDirectory: URL

    /// Enumerates `.jsonl` files under `directories`. Covered descendant roots are
    /// removed before the `fts(3)` walks; names are then collected without statting,
    /// and the per-file mtime/size reads run on all cores.
    func usageFiles(in directories: [URL], modifiedSince: Date) -> [CodingUsageFile] {
        let configuredPaths = directories.map { $0.standardizedFileURL.path }.uniqued(by: \.self)
        let rootPaths = configuredPaths.filter { candidate in
            !configuredPaths.contains { ancestor in
                candidate != ancestor
                    && (ancestor == "/" || candidate.hasPrefix(ancestor + "/"))
            }
        }
        let candidates = rootPaths.flatMap(jsonlPaths)

        let files = concurrentMap(candidates) { path -> CodingUsageFile? in
            guard let file = usageFile(path: path) else {
                return nil
            }
            if file.modifiedAt < modifiedSince {
                return nil
            }
            return file
        }
        return files.compactMap { $0 }.sorted { $0.path < $1.path }
    }

    /// Walks `rootPath` and returns every `.jsonl` file path under it. `FTS_NOSTAT`
    /// keeps the walk on `readdir` and `d_type` alone, so it costs one syscall per
    /// directory instead of one per entry. Symlinks are reported but not followed,
    /// matching the metadata stage's `lstat`.
    private func jsonlPaths(under rootPath: String) -> [String] {
        guard let duplicatedRootPath = strdup(rootPath) else {
            return []
        }
        var argv = [duplicatedRootPath, nil]
        defer { free(duplicatedRootPath) }
        guard
            let stream = argv.withUnsafeMutableBufferPointer({
                fts_open($0.baseAddress!, FTS_PHYSICAL | FTS_NOSTAT | FTS_NOCHDIR, nil)
            })
        else {
            return []
        }
        defer { fts_close(stream) }

        var paths: [String] = []
        while let entry = fts_read(stream) {
            let node = entry.pointee
            switch Int32(node.fts_info) {
            case FTS_F, FTS_NSOK:
                // Suffix match with a non-empty stem, as `pathExtension == "jsonl"` had.
                let length = Int(node.fts_pathlen)
                guard
                    length > 6,
                    strncmp(node.fts_path + length - 6, ".jsonl", 6) == 0,
                    node.fts_path[length - 7] != UInt8(ascii: "/")
                else {
                    break
                }
                paths.append(String(cString: node.fts_path))
            default:
                break
            }
        }
        return paths
    }

    private func usageFile(path: String) -> CodingUsageFile? {
        var status = stat()
        guard lstat(path, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else {
            return nil
        }
        let modifiedAt = Date(
            timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec)
                + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        return CodingUsageFile(
            path: path,
            modifiedAt: modifiedAt,
            byteCount: Int(status.st_size)
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
