import Foundation
import Observation

@MainActor
@Observable
final class WalkHistoryStore {
    private static let storageKey = "walkHistory"

    private(set) var walkCountsByDay: [Date: Int]

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.load(from: defaults)
        self.walkCountsByDay = loaded.counts
        let pruned = Self.pruneOldEntries(in: &walkCountsByDay)

        if loaded.needsSave || pruned {
            save()
        }
    }

    func recordWalk(_ date: Date = .now) {
        let day = Calendar.current.startOfDay(for: date)
        walkCountsByDay[day, default: 0] += 1
        Self.pruneOldEntries(in: &walkCountsByDay)
        save()
    }

    private static func load(from defaults: UserDefaults) -> LoadedWalkHistory {
        guard let data = defaults.data(forKey: storageKey) else {
            return LoadedWalkHistory(counts: [:], needsSave: false)
        }

        if let days = try? JSONDecoder().decode([StoredWalkDay].self, from: data) {
            return LoadedWalkHistory(
                counts: days.reduce(into: [:]) { counts, day in
                    counts[day.day, default: 0] += day.count
                },
                needsSave: false
            )
        }

        if let dates = try? JSONDecoder().decode([Date].self, from: data) {
            return LoadedWalkHistory(
                counts: dates.reduce(into: [:]) { counts, walk in
                    counts[Calendar.current.startOfDay(for: walk), default: 0] += 1
                },
                needsSave: true
            )
        }

        return LoadedWalkHistory(counts: [:], needsSave: false)
    }

    private func save() {
        let days =
            walkCountsByDay
            .map { StoredWalkDay(day: $0.key, count: $0.value) }
            .sorted { $0.day < $1.day }
        guard let data = try? JSONEncoder().encode(days) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    @discardableResult
    private static func pruneOldEntries(in counts: inout [Date: Int]) -> Bool {
        let previousCount = counts.count
        let cutoff = HistoryRetention.earliestMonth()
        counts = counts.filter { $0.key >= cutoff }
        return counts.count != previousCount
    }
}

private struct LoadedWalkHistory {
    let counts: [Date: Int]
    let needsSave: Bool
}

private struct StoredWalkDay: Codable {
    let day: Date
    let count: Int
}
