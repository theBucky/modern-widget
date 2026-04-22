import Foundation

@MainActor
final class WalkHistoryStore: ObservableObject {
    private static let storageKey = "walkHistory"
    private static let retentionMonths = 3

    @Published private(set) var walks: [Date] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedWalks = load()
        var prunedWalks = loadedWalks
        Self.pruneOldEntries(in: &prunedWalks)
        self.walks = prunedWalks

        if loadedWalks.count != prunedWalks.count {
            save()
        }
    }

    func recordWalk(_ date: Date = .now) {
        walks.append(date)
        Self.pruneOldEntries(in: &walks)
        save()
    }

    func walkCountsByDay() -> [Date: Int] {
        walks.reduce(into: [:]) { counts, walk in
            counts[Calendar.current.startOfDay(for: walk), default: 0] += 1
        }
    }

    static func earliestRetainedMonth(now: Date = .now) -> Date {
        let calendar = Calendar.current
        let currentMonthStart = calendar.dateInterval(of: .month, for: now)!.start
        return calendar.date(
            byAdding: .month,
            value: -(retentionMonths - 1),
            to: currentMonthStart
        )!
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
        let cutoff = earliestRetainedMonth()
        walks.removeAll { $0 < cutoff }
    }
}
