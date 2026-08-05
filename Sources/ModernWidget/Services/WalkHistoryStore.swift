import Foundation
import Observation

@MainActor
@Observable
final class WalkHistoryStore {
    private var journal: LocalDayJournal

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.journal = LocalDayJournal(storageKey: "walkHistory", defaults: defaults, now: now)
    }

    func recordWalk(on day: LocalDay, now: Date) {
        let count = journal.counts[day, default: 0]
        journal.setCount(count == .max ? count : count + 1, on: day, now: now)
    }

    func walkCount(on day: LocalDay) -> Int {
        journal.counts[day] ?? 0
    }
}
