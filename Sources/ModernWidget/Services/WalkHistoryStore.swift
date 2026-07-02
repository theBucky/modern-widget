import Foundation
import Observation

@MainActor
@Observable
final class WalkHistoryStore {
    private static let storageKey = "walkHistory"

    private var countsByDay: [LocalDay: Int]

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.load(from: defaults)
        var counts = loaded.counts
        let pruned = Self.pruneOldEntries(in: &counts)
        self.countsByDay = counts

        if loaded.needsSave || pruned {
            save()
        }
    }

    func recordWalk(_ date: Date = .now) {
        countsByDay[LocalDay(date: date), default: 0] += 1
        Self.pruneOldEntries(in: &countsByDay)
        save()
    }

    func walkCount(on date: Date) -> Int {
        countsByDay[LocalDay(date: date)] ?? 0
    }

    private static func load(from defaults: UserDefaults) -> (
        counts: [LocalDay: Int], needsSave: Bool
    ) {
        guard let data = defaults.data(forKey: storageKey) else {
            return (counts: [:], needsSave: false)
        }

        if let stored = try? JSONDecoder().decode([StoredWalkDay].self, from: data) {
            var counts: [LocalDay: Int] = [:]
            var droppedInvalid = false
            for record in stored {
                guard record.count > 0,
                    let day = LocalDay(year: record.year, month: record.month, day: record.day)
                else {
                    droppedInvalid = true
                    continue
                }
                counts[day, default: 0] += record.count
            }
            return (counts: counts, needsSave: droppedInvalid)
        }

        return (counts: [:], needsSave: false)
    }

    private func save() {
        let records =
            countsByDay
            .sorted { $0.key < $1.key }
            .map {
                StoredWalkDay(
                    year: $0.key.year, month: $0.key.month, day: $0.key.day, count: $0.value)
            }
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    @discardableResult
    private static func pruneOldEntries(in counts: inout [LocalDay: Int]) -> Bool {
        let previousCount = counts.count
        let cutoff = HistoryRetention.earliestRetainedDay()
        counts = counts.filter { $0.key >= cutoff }
        return counts.count != previousCount
    }
}

private struct StoredWalkDay: Codable {
    let year: Int
    let month: Int
    let day: Int
    let count: Int
}
