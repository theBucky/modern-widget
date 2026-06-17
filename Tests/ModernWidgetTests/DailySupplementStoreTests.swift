import Foundation
import Testing

@testable import ModernWidget

@MainActor
@Suite("Daily supplement store")
struct DailySupplementStoreTests {
    @Test("taken status is stored per calendar day")
    func takenStatusIsStoredPerCalendarDay() {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let store = DailySupplementStore(defaults: defaults)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let morning = calendar.date(byAdding: .hour, value: 8, to: today)!
        let evening = calendar.date(byAdding: .hour, value: 21, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        store.setTaken(true, on: evening)

        let reloadedStore = DailySupplementStore(defaults: defaults)
        #expect(reloadedStore.isTaken(on: morning))
        #expect(reloadedStore.isTaken(on: evening))
        #expect(!reloadedStore.isTaken(on: tomorrow))
    }

    @Test("clearing one day leaves other days alone")
    func clearingOneDayLeavesOtherDaysAlone() {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let store = DailySupplementStore(defaults: defaults)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        store.setTaken(true, on: today)
        store.setTaken(true, on: tomorrow)
        store.setTaken(false, on: today)

        #expect(!store.isTaken(on: today))
        #expect(store.isTaken(on: tomorrow))
    }

    @Test("days outside the retention window are ignored")
    func daysOutsideRetentionWindowAreIgnored() {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let store = DailySupplementStore(defaults: defaults)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let expiredDay = calendar.date(byAdding: .month, value: -4, to: today)!

        store.setTaken(true, on: expiredDay)
        store.setTaken(true, on: today)

        let reloadedStore = DailySupplementStore(defaults: defaults)
        #expect(!reloadedStore.isTaken(on: expiredDay))
        #expect(reloadedStore.isTaken(on: today))
    }
}
