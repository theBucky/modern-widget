import Foundation
import Observation

@MainActor
@Observable
final class DailySupplementStore {
    private static let storageKey = "dailySupplementTakenDays"

    private var takenDays: Set<Date>

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.takenDays = Self.load(from: defaults)
        pruneOldEntries()
    }

    var isTakenToday: Bool {
        get { isTaken(on: .now) }
        set { setTaken(newValue) }
    }

    func isTaken(on date: Date) -> Bool {
        takenDays.contains(Calendar.current.startOfDay(for: date))
    }

    func setTaken(_ isTaken: Bool, on date: Date = .now) {
        let day = Calendar.current.startOfDay(for: date)

        if isTaken {
            takenDays.insert(day)
        } else {
            takenDays.remove(day)
        }

        pruneOldEntries()
        save()
    }

    private func pruneOldEntries() {
        takenDays = takenDays.filter { $0 >= HistoryRetention.earliestMonth() }
    }

    private static func load(from defaults: UserDefaults) -> Set<Date> {
        guard let data = defaults.data(forKey: storageKey),
            let dates = try? JSONDecoder().decode(Set<Date>.self, from: data)
        else {
            return []
        }
        return dates
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(takenDays) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
