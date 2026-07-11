import Darwin
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
    /// Enumerates `.jsonl` files under `directory`. The name walk runs on `fts(3)`
    /// without statting anything, then the per-file mtime/size fingerprints, the bulk
    /// of the sweep's syscalls, stat on all cores.
    func usageFiles(in directory: URL, modifiedSince: Date) -> [CodingUsageFile] {
        let directoryPath = directory.path
        let candidates = jsonlPaths(under: directoryPath)

        let files = concurrentMap(candidates) { path -> CodingUsageFile? in
            guard let fingerprint = usageFileFingerprint(path: path) else {
                return nil
            }
            if let modifiedAt = fingerprint.modifiedAt, modifiedAt < modifiedSince {
                return nil
            }
            return CodingUsageFile(
                url: URL(fileURLWithPath: path, isDirectory: false),
                fingerprint: fingerprint
            )
        }
        return files.compactMap { $0 }.sorted { $0.fingerprint.path < $1.fingerprint.path }
    }

    /// Walks `rootPath` and returns every `.jsonl` file path under it. `FTS_NOSTAT`
    /// keeps the walk on `readdir` and `d_type` alone, so it costs one syscall per
    /// directory instead of one per entry. Symlinks are reported but not followed,
    /// matching the fingerprint stage's `lstat`.
    private func jsonlPaths(under rootPath: String) -> [String] {
        var argv = [strdup(rootPath), nil]
        defer { free(argv[0]) }
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

    /// By default symlinks and other non-regular files are excluded, matching the
    /// physical `fts` walk. `resolvingSymlinks` stats through a link instead, for
    /// config files whose readers also follow it: the link's own attributes never
    /// change when its target is edited, so only the target's fingerprint can
    /// detect the edit.
    func usageFileFingerprint(
        path: String, resolvingSymlinks: Bool = false
    ) -> CodingUsageFileFingerprint? {
        var status = stat()
        let statted = resolvingSymlinks ? stat(path, &status) : lstat(path, &status)
        guard statted == 0, (status.st_mode & S_IFMT) == S_IFREG else {
            return nil
        }
        let modifiedAt = Date(
            timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec)
                + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        return CodingUsageFileFingerprint(
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
