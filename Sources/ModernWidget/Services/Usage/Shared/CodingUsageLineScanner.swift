import Darwin
import Foundation

/// Reads small files, maps large files, and hands each non-empty line to `visit` as a
/// borrowed byte slice. Newlines are located with `memchr`; slicing `Data` per line is
/// much slower because every byte pays Collection witness and bounds-check overhead.
func forEachJSONLine(
    in file: CodingUsageFile,
    _ visit: (UnsafeRawBufferPointer) -> Void
) {
    let directReadByteLimit = 128 * 1024
    let options: Data.ReadingOptions =
        file.byteCount < directReadByteLimit ? [] : .mappedIfSafe
    guard let data = try? Data(contentsOf: file.url, options: options), !data.isEmpty else {
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

/// Maps independent elements on all cores while preserving input order.
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
