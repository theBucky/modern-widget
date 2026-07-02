import Darwin
import Foundation

extension CodingUsageLoader {
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
}
