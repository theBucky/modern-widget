import Foundation
import Observation

@MainActor
@Observable
final class DailySupplementStore {
    private var journal: LocalDayJournal

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.journal = LocalDayJournal(
            storageKey: "dailySupplementTakenDays",
            defaults: defaults,
            now: now
        )
    }

    var isTakenToday: Bool {
        get { isTaken(on: LocalDay(date: .now)) }
        set { setTaken(newValue) }
    }

    func isTaken(on day: LocalDay) -> Bool {
        journal.counts[day, default: 0] > 0
    }

    func setTaken(_ isTaken: Bool, on date: Date = .now, now: Date = .now) {
        journal.setCount(isTaken ? 1 : 0, on: LocalDay(date: date), now: now)
    }
}
