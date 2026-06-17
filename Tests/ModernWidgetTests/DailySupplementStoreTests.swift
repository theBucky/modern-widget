import Foundation
import Testing

@testable import ModernWidget

@MainActor
@Suite("Daily supplement store")
struct DailySupplementStoreTests {
    @Test("taken days persist by calendar day")
    func takenDaysPersistByCalendarDay() {
        let defaults = makeDefaults()
        let store = DailySupplementStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: .now)
        let evening = Calendar.current.date(byAdding: .hour, value: 21, to: today)!

        store.setTaken(true, on: today)

        let reloadedStore = DailySupplementStore(defaults: defaults)
        #expect(reloadedStore.isTaken(on: evening))
    }

    @Test("clearing a day removes taken status")
    func clearingDayRemovesTakenStatus() {
        let defaults = makeDefaults()
        let store = DailySupplementStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: .now)

        store.setTaken(true, on: today)
        store.setTaken(false, on: today)

        #expect(!store.isTaken(on: today))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DailySupplementStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
