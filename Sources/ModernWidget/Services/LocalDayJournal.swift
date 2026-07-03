import Foundation

/// `Record` must encode as a keyed object: its fields flatten into the same JSON object
/// as the day fields to preserve the flat on-disk shape, so a single-value or unkeyed
/// record would fail at encode or read back as malformed.
struct LocalDayJournal<Record: Codable & Sendable>: Sendable {
    let storageKey: String

    private let isPersistent: @Sendable (Record) -> Bool
    private let merge: @Sendable (inout Record, Record) -> Void

    init(
        storageKey: String,
        isPersistent: @escaping @Sendable (Record) -> Bool = { _ in true },
        merge: @escaping @Sendable (inout Record, Record) -> Void = { _, _ in }
    ) {
        self.storageKey = storageKey
        self.isPersistent = isPersistent
        self.merge = merge
    }

    func load(
        from defaults: UserDefaults,
        now: Date = .now
    ) -> (records: [LocalDay: Record], needsSave: Bool) {
        guard let data = defaults.data(forKey: storageKey) else {
            return (records: [:], needsSave: false)
        }

        guard let storedRecords = try? JSONDecoder().decode([StoredRecord<Record>].self, from: data)
        else {
            return (records: [:], needsSave: true)
        }

        let cutoff = HistoryRetention.earliestRetainedDay(now: now)
        var records: [LocalDay: Record] = [:]
        var needsSave = false

        for storedRecord in storedRecords {
            guard let day = storedRecord.localDay,
                day >= cutoff,
                isPersistent(storedRecord.record)
            else {
                needsSave = true
                continue
            }

            if var existingRecord = records[day] {
                merge(&existingRecord, storedRecord.record)
                records[day] = existingRecord
                needsSave = true
            } else {
                records[day] = storedRecord.record
            }
        }

        return (records: records, needsSave: needsSave)
    }

    func save(_ records: [LocalDay: Record], to defaults: UserDefaults) {
        let storedRecords =
            records
            .sorted { $0.key < $1.key }
            .map { StoredRecord(day: $0.key, record: $0.value) }
        guard let data = try? JSONEncoder().encode(storedRecords) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct LocalDayJournalUnitRecord: Codable, Sendable {}

struct LocalDayJournalCountRecord: Codable, Sendable {
    var count: Int
}

private struct StoredRecord<Record: Codable>: Codable {
    let year: Int
    let month: Int
    let day: Int
    let record: Record

    init(day: LocalDay, record: Record) {
        self.year = day.year
        self.month = day.month
        self.day = day.day
        self.record = record
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DayCodingKeys.self)
        self.year = try container.decode(Int.self, forKey: .year)
        self.month = try container.decode(Int.self, forKey: .month)
        self.day = try container.decode(Int.self, forKey: .day)
        self.record = try Record(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DayCodingKeys.self)
        try container.encode(year, forKey: .year)
        try container.encode(month, forKey: .month)
        try container.encode(day, forKey: .day)
        try record.encode(to: encoder)
    }

    var localDay: LocalDay? {
        LocalDay(year: year, month: month, day: day)
    }

    private enum DayCodingKeys: String, CodingKey {
        case year, month, day
    }
}
