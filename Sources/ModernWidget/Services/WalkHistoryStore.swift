import Foundation

@MainActor
final class WalkHistoryStore: ObservableObject {
    private static let storageKey = "walkHistory"
    private static let retentionDays = 30

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

    func walksByDay() -> [(day: Date, count: Int)] {
        Dictionary(grouping: walks) { Calendar.current.startOfDay(for: $0) }
            .map { (day: $0.key, count: $0.value.count) }
            .sorted { $0.day > $1.day }
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
        let now = Date.now
        let cutoff =
            Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: now) ?? now
        walks.removeAll { $0 < cutoff }
    }
}
