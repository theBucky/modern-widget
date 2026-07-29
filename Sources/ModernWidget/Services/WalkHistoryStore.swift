import Foundation
import Observation

@MainActor
@Observable
final class WalkHistoryStore {
    private var journal: LocalDayJournal

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.journal = LocalDayJournal(storageKey: "walkHistory", defaults: defaults, now: now)
    }

    func recordWalk(_ date: Date = .now, now: Date = .now) {
        let day = LocalDay(date: date)
        let count = journal.counts[day, default: 0]
        journal.setCount(count == .max ? count : count + 1, on: day, now: now)
    }

    func walkCount(on day: LocalDay) -> Int {
        journal.counts[day] ?? 0
    }
}
