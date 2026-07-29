import Foundation

/// Per-day counts persisted in UserDefaults as a flat `[{year, month, day, count}]`
/// array. Loading parses every record, sums duplicate days, drops invalid days and
/// non-positive counts, prunes days outside the retention window, and rewrites
/// storage whenever it corrected anything, so persisted data is clean after one load.
struct LocalDayJournal {
    private(set) var counts: [LocalDay: Int]

    private let storageKey: String
    private let defaults: UserDefaults

    init(storageKey: String, defaults: UserDefaults, now: Date) {
        self.storageKey = storageKey
        self.defaults = defaults
        self.counts = [:]

        guard let data = defaults.data(forKey: storageKey) else {
            return
        }
        guard let records = try? JSONDecoder().decode([StoredDay].self, from: data) else {
            save()
            return
        }

        let cutoff = HistoryRetention.earliestRetainedDay(now: now)
        var needsSave = false
        for record in records {
            guard let day = record.localDay, day >= cutoff, record.count > 0 else {
                needsSave = true
                continue
            }
            let existing = counts[day]
            if existing != nil {
                needsSave = true
            }
            let (sum, overflow) = (existing ?? 0).addingReportingOverflow(record.count)
            counts[day] = overflow ? .max : sum
        }
        if needsSave {
            save()
        }
    }

    /// Sets a day's count (a non-positive count removes the day), prunes days that
    /// fell out of the retention window, and persists.
    mutating func setCount(_ count: Int, on day: LocalDay, now: Date) {
        let cutoff = HistoryRetention.earliestRetainedDay(now: now)
        counts[day] = count > 0 ? count : nil
        counts = counts.filter { $0.key >= cutoff }
        save()
    }

    private func save() {
        let records =
            counts
            .sorted { $0.key < $1.key }
            .map { StoredDay(day: $0.key, count: $0.value) }
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

private struct StoredDay: Codable {
    let year: Int
    let month: Int
    let day: Int
    let count: Int

    init(day: LocalDay, count: Int) {
        self.year = day.year
        self.month = day.month
        self.day = day.day
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.year = try container.decode(Int.self, forKey: .year)
        self.month = try container.decode(Int.self, forKey: .month)
        self.day = try container.decode(Int.self, forKey: .day)
        // Older supplement records carry no count; presence in the array meant taken.
        self.count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
    }

    var localDay: LocalDay? {
        LocalDay(year: year, month: month, day: day)
    }
}
