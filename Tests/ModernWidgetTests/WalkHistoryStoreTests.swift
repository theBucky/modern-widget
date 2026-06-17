import Foundation
import Testing

@testable import ModernWidget

@MainActor
@Suite("Walk history store")
struct WalkHistoryStoreTests {
    @Test("walks on the same calendar day are counted separately and persisted")
    func walksOnSameCalendarDayAreCountedSeparatelyAndPersisted() {
        let defaults = makeDefaults("WalkHistoryStoreTests")
        let store = WalkHistoryStore(defaults: defaults)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let morning = calendar.date(byAdding: .hour, value: 9, to: today)!
        let evening = calendar.date(byAdding: .hour, value: 18, to: today)!

        store.recordWalk(morning)
        store.recordWalk(evening)

        let reloadedStore = WalkHistoryStore(defaults: defaults)
        #expect(store.walkCountsByDay[today] == 2)
        #expect(reloadedStore.walkCountsByDay[today] == 2)
    }

    @Test("walks outside the retention window are ignored")
    func walksOutsideRetentionWindowAreIgnored() {
        let defaults = makeDefaults("WalkHistoryStoreTests")
        let store = WalkHistoryStore(defaults: defaults)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let expiredDay = calendar.date(byAdding: .month, value: -4, to: today)!

        store.recordWalk(expiredDay)
        store.recordWalk(today)

        let reloadedStore = WalkHistoryStore(defaults: defaults)
        #expect(reloadedStore.walkCountsByDay[calendar.startOfDay(for: expiredDay)] == nil)
        #expect(reloadedStore.walkCountsByDay[today] == 1)
    }
}
