import Synchronization

/// Caches immutable parsed records by the file identity captured during discovery.
/// Replacing the index after each load also evicts deleted and superseded files.
final class CodingUsageFileCache<Record: Sendable>: Sendable {
    typealias RecordsByFile = [CodingUsageFile: [Record]]

    private let records = Mutex(RecordsByFile())

    func snapshot() -> RecordsByFile {
        records.withLock { $0 }
    }

    func replace(with newRecords: RecordsByFile) {
        records.withLock { $0 = newRecords }
    }
}
