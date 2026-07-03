import Foundation
import Observation

@MainActor
@Observable
final class DailySupplementStore {
    private static let journal = LocalDayJournal<LocalDayJournalUnitRecord>(
        storageKey: "dailySupplementTakenDays"
    )

    private var takenDays: Set<LocalDay>

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        let loaded = Self.journal.load(from: defaults, now: now)
        self.takenDays = Set(loaded.records.keys)

        if loaded.needsSave {
            save()
        }
    }

    var isTakenToday: Bool {
        get { isTaken(on: .now) }
        set { setTaken(newValue) }
    }

    func isTaken(on date: Date) -> Bool {
        takenDays.contains(LocalDay(date: date))
    }

    func setTaken(_ isTaken: Bool, on date: Date = .now, now: Date = .now) {
        let day = LocalDay(date: date)

        if isTaken {
            takenDays.insert(day)
        } else {
            takenDays.remove(day)
        }

        let cutoff = HistoryRetention.earliestRetainedDay(now: now)
        takenDays = takenDays.filter { $0 >= cutoff }
        save()
    }

    private func save() {
        let records = Dictionary(
            uniqueKeysWithValues: takenDays.map { ($0, LocalDayJournalUnitRecord()) }
        )
        Self.journal.save(records, to: defaults)
    }
}
