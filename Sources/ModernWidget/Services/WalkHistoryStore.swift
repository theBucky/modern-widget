import Foundation
import Observation

@MainActor
@Observable
final class WalkHistoryStore {
    private static let journal = LocalDayJournal<LocalDayJournalCountRecord>(
        storageKey: "walkHistory",
        isPersistent: { $0.count > 0 },
        merge: { existing, new in existing.count += new.count }
    )

    private var countsByDay: [LocalDay: Int]

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        let loaded = Self.journal.load(from: defaults, now: now)
        self.countsByDay = loaded.records.mapValues(\.count)

        if loaded.needsSave {
            save()
        }
    }

    func recordWalk(_ date: Date = .now, now: Date = .now) {
        countsByDay[LocalDay(date: date), default: 0] += 1
        let cutoff = HistoryRetention.earliestRetainedDay(now: now)
        countsByDay = countsByDay.filter { $0.key >= cutoff }
        save()
    }

    func walkCount(on date: Date) -> Int {
        countsByDay[LocalDay(date: date)] ?? 0
    }

    private func save() {
        let records = countsByDay.mapValues { LocalDayJournalCountRecord(count: $0) }
        Self.journal.save(records, to: defaults)
    }
}
