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
        #expect(store.walkCount(on: today) == 2)
        #expect(reloadedStore.walkCount(on: today) == 2)
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
        #expect(reloadedStore.walkCount(on: expiredDay) == 0)
        #expect(reloadedStore.walkCount(on: today) == 1)
    }

    @Test("legacy walk dates are folded by day and migrated")
    func legacyWalkDatesAreFoldedByDayAndMigrated() throws {
        let defaults = makeDefaults("WalkHistoryStoreTests")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let morning = calendar.date(byAdding: .hour, value: 9, to: today)!
        let evening = calendar.date(byAdding: .hour, value: 18, to: today)!
        let legacyData = try JSONEncoder().encode([morning, evening])
        defaults.set(legacyData, forKey: "walkHistory")

        let store = WalkHistoryStore(defaults: defaults)
        let reloadedStore = WalkHistoryStore(defaults: defaults)
        let savedData = try #require(defaults.data(forKey: "walkHistory"))
        let savedDays = try JSONDecoder().decode([StoredWalkDay].self, from: savedData)

        #expect(store.walkCount(on: today) == 2)
        #expect(reloadedStore.walkCount(on: today) == 2)
        #expect(savedDays == [StoredWalkDay(day: today, count: 2)])
    }

    private struct StoredWalkDay: Codable, Equatable {
        let year: Int
        let month: Int
        let day: Int
        let count: Int

        init(day: Date, count: Int) {
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            self.year = components.year!
            self.month = components.month!
            self.day = components.day!
            self.count = count
        }
    }
}
