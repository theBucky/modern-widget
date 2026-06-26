import Foundation
import Observation

@MainActor
@Observable
final class WalkHistoryStore {
    private static let storageKey = "walkHistory"

    private var countsByDayID: [WalkHistoryDay: Int]

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.load(from: defaults)
        var counts = loaded.counts
        let pruned = Self.pruneOldEntries(in: &counts)
        self.countsByDayID = counts

        if loaded.needsSave || pruned {
            save()
        }
    }

    func recordWalk(_ date: Date = .now) {
        let day = WalkHistoryDay(date: date)
        countsByDayID[day, default: 0] += 1
        Self.pruneOldEntries(in: &countsByDayID)
        save()
    }

    func walkCount(on date: Date) -> Int {
        countsByDayID[WalkHistoryDay(date: date)] ?? 0
    }

    private static func load(from defaults: UserDefaults) -> LoadedWalkHistory {
        guard let data = defaults.data(forKey: storageKey) else {
            return LoadedWalkHistory(counts: [:], needsSave: false)
        }

        if let days = try? JSONDecoder().decode([StoredWalkDay].self, from: data) {
            return LoadedWalkHistory(
                counts: days.reduce(into: [:]) { counts, day in
                    counts[day.historyDay, default: 0] += day.count
                },
                needsSave: false
            )
        }

        if let days = try? JSONDecoder().decode([LegacyStoredWalkDay].self, from: data) {
            return LoadedWalkHistory(
                counts: days.reduce(into: [:]) { counts, day in
                    counts[WalkHistoryDay(date: day.day), default: 0] += day.count
                },
                needsSave: true
            )
        }

        if let dates = try? JSONDecoder().decode([Date].self, from: data) {
            return LoadedWalkHistory(
                counts: dates.reduce(into: [:]) { counts, walk in
                    counts[WalkHistoryDay(date: walk), default: 0] += 1
                },
                needsSave: true
            )
        }

        return LoadedWalkHistory(counts: [:], needsSave: false)
    }

    private func save() {
        let days =
            countsByDayID
            .map { StoredWalkDay(day: $0.key, count: $0.value) }
            .sorted { $0.historyDay < $1.historyDay }
        guard let data = try? JSONEncoder().encode(days) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    @discardableResult
    private static func pruneOldEntries(in counts: inout [WalkHistoryDay: Int]) -> Bool {
        let previousCount = counts.count
        let cutoff = WalkHistoryDay(date: HistoryRetention.earliestMonth())
        counts = counts.filter { $0.key >= cutoff }
        return counts.count != previousCount
    }
}

private struct LoadedWalkHistory {
    let counts: [WalkHistoryDay: Int]
    let needsSave: Bool
}

private struct StoredWalkDay: Codable {
    let year: Int
    let month: Int
    let day: Int
    let count: Int

    init(day: WalkHistoryDay, count: Int) {
        self.year = day.year
        self.month = day.month
        self.day = day.day
        self.count = count
    }

    var historyDay: WalkHistoryDay {
        WalkHistoryDay(year: year, month: month, day: day)
    }
}

private struct LegacyStoredWalkDay: Codable {
    let day: Date
    let count: Int
}

private struct WalkHistoryDay: Comparable, Codable, Hashable {
    private static let calendar = Calendar(identifier: .gregorian)

    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date) {
        let components = Self.calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year!
        self.month = components.month!
        self.day = components.day!
    }

    static func < (lhs: WalkHistoryDay, rhs: WalkHistoryDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
