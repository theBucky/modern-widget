import Synchronization

/// Caches immutable parsed values by the file identity captured during discovery.
/// Replacing the index after each load also evicts deleted and superseded files.
final class CodingUsageFileCache<Value: Sendable>: Sendable {
    typealias ValuesByFile = [CodingUsageFile: Value]

    private let values = Mutex(ValuesByFile())

    func snapshot() -> ValuesByFile {
        values.withLock { $0 }
    }

    func replace(with newValues: ValuesByFile) {
        values.withLock { $0 = newValues }
    }
}
