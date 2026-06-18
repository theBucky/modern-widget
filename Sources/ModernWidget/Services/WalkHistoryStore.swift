import Foundation
import Observation

@MainActor
@Observable
final class WalkHistoryStore {
    private static let storageKey = "walkHistory"

    private(set) var walkCountsByDay: [Date: Int] = [:]

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private var walks: [Date] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        walks = load()
        let loadedCount = walks.count
        Self.pruneOldEntries(in: &walks)
        updateWalkCountsByDay()

        if walks.count != loadedCount {
            save()
        }
    }

    func recordWalk(_ date: Date = .now) {
        walks.append(date)
        Self.pruneOldEntries(in: &walks)
        updateWalkCountsByDay()
        save()
    }

    private func updateWalkCountsByDay() {
        walkCountsByDay = walks.reduce(into: [:]) { counts, walk in
            counts[Calendar.current.startOfDay(for: walk), default: 0] += 1
        }
    }

    private func load() -> [Date] {
        guard let data = defaults.data(forKey: Self.storageKey),
            let dates = try? JSONDecoder().decode([Date].self, from: data)
        else {
            return []
        }
        return dates
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(walks) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func pruneOldEntries(in walks: inout [Date]) {
        let cutoff = HistoryRetention.earliestMonth()
        walks.removeAll { $0 < cutoff }
    }
}
