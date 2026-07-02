import Foundation
import Observation

@MainActor
@Observable
final class DailySupplementStore {
    private static let storageKey = "dailySupplementTakenDays"

    private var takenDays: Set<LocalDay>

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.load(from: defaults)
        var days = loaded.days
        let pruned = Self.pruneOldEntries(in: &days)
        self.takenDays = days

        if loaded.needsSave || pruned {
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

    func setTaken(_ isTaken: Bool, on date: Date = .now) {
        let day = LocalDay(date: date)

        if isTaken {
            takenDays.insert(day)
        } else {
            takenDays.remove(day)
        }

        Self.pruneOldEntries(in: &takenDays)
        save()
    }

    private static func load(from defaults: UserDefaults) -> (days: Set<LocalDay>, needsSave: Bool)
    {
        guard let data = defaults.data(forKey: storageKey) else {
            return (days: [], needsSave: false)
        }

        if let stored = try? JSONDecoder().decode([StoredSupplementDay].self, from: data) {
            let days = Set(stored.compactMap(\.localDay))
            return (days: days, needsSave: days.count != stored.count)
        }

        return (days: [], needsSave: true)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(takenDays) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    @discardableResult
    private static func pruneOldEntries(in days: inout Set<LocalDay>) -> Bool {
        let previousCount = days.count
        let cutoff = HistoryRetention.earliestRetainedDay()
        days = days.filter { $0 >= cutoff }
        return days.count != previousCount
    }
}

private struct StoredSupplementDay: Decodable {
    let year: Int
    let month: Int
    let day: Int

    /// `nil` drops persisted identities that no longer name a valid Gregorian day.
    var localDay: LocalDay? {
        LocalDay(year: year, month: month, day: day)
    }
}
