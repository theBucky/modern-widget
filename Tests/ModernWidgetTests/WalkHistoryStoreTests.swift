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

    @Test("the retention cutoff day stays visible while the day before is pruned")
    func retentionCutoffDayIsInclusive() {
        let defaults = makeDefaults("WalkHistoryStoreTests")
        let store = WalkHistoryStore(defaults: defaults)
        let calendar = Calendar.current
        let cutoffDay = HistoryRetention.earliestMonth()
        let dayBeforeCutoff = calendar.date(byAdding: .day, value: -1, to: cutoffDay)!

        store.recordWalk(cutoffDay)
        store.recordWalk(dayBeforeCutoff)

        let reloadedStore = WalkHistoryStore(defaults: defaults)
        #expect(reloadedStore.walkCount(on: cutoffDay) == 1)
        #expect(reloadedStore.walkCount(on: dayBeforeCutoff) == 0)
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

    @Test("invalid persisted walk counts are dropped before same-day aggregation")
    func invalidPersistedWalkCountsAreDropped() throws {
        let defaults = makeDefaults("WalkHistoryStoreTests")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let records = [StoredWalkDay(day: today, count: 2), StoredWalkDay(day: today, count: -1)]
        defaults.set(try JSONEncoder().encode(records), forKey: "walkHistory")

        let store = WalkHistoryStore(defaults: defaults)
        let reloadedStore = WalkHistoryStore(defaults: defaults)

        #expect(store.walkCount(on: today) == 2)
        #expect(reloadedStore.walkCount(on: today) == 2)
    }

    @Test("invalid persisted walk day identities are dropped and not resurrected")
    func invalidPersistedWalkDaysAreDropped() throws {
        let defaults = makeDefaults("WalkHistoryStoreTests")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let validRecord = StoredWalkDay(day: today, count: 3)
        let invalidRecord = StoredWalkDay(year: validRecord.year, month: 13, day: 40, count: 5)
        defaults.set(try JSONEncoder().encode([validRecord, invalidRecord]), forKey: "walkHistory")

        let store = WalkHistoryStore(defaults: defaults)
        let reloadedStore = WalkHistoryStore(defaults: defaults)
        let savedData = try #require(defaults.data(forKey: "walkHistory"))
        let savedDays = try JSONDecoder().decode([StoredWalkDay].self, from: savedData)

        #expect(store.walkCount(on: today) == 3)
        #expect(reloadedStore.walkCount(on: today) == 3)
        #expect(savedDays == [validRecord])
    }

    private struct StoredWalkDay: Codable, Equatable {
        let year: Int
        let month: Int
        let day: Int
        let count: Int

        init(year: Int, month: Int, day: Int, count: Int) {
            self.year = year
            self.month = month
            self.day = day
            self.count = count
        }

        init(day: Date, count: Int) {
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            self.init(
                year: components.year!, month: components.month!, day: components.day!, count: count
            )
        }
    }
}
