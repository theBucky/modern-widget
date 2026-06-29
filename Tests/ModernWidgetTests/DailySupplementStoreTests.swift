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

    @Test("loading prunes expired persisted days")
    func loadingPrunesExpiredPersistedDays() throws {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let expiredDay = calendar.date(byAdding: .month, value: -4, to: today)!
        let storedDays: Set<Date> = [expiredDay, today]

        defaults.set(
            try JSONEncoder().encode(storedDays),
            forKey: "dailySupplementTakenDays"
        )

        _ = DailySupplementStore(defaults: defaults)
        let reloadedStore = DailySupplementStore(defaults: defaults)

        #expect(reloadedStore.isTaken(on: today))
        #expect(!reloadedStore.isTaken(on: expiredDay))
        let savedData = try #require(defaults.data(forKey: "dailySupplementTakenDays"))
        let savedDays = try JSONDecoder().decode(Set<LocalDay>.self, from: savedData)
        #expect(savedDays == [LocalDay(date: today)])
    }

    @Test("persisted dates with arbitrary times normalize to one local day")
    func persistedDatesNormalizeToLocalDays() throws {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let morning = calendar.date(byAdding: .hour, value: 8, to: today)!
        let evening = calendar.date(byAdding: .hour, value: 21, to: today)!
        let legacyDays: Set<Date> = [morning, evening]

        defaults.set(
            try JSONEncoder().encode(legacyDays),
            forKey: "dailySupplementTakenDays"
        )

        let store = DailySupplementStore(defaults: defaults)
        #expect(store.isTaken(on: today))
        #expect(store.isTaken(on: morning))
        #expect(store.isTaken(on: evening))

        let savedData = try #require(defaults.data(forKey: "dailySupplementTakenDays"))
        let savedDays = try JSONDecoder().decode(Set<LocalDay>.self, from: savedData)
        #expect(savedDays == [LocalDay(date: today)])
        #expect((try? JSONDecoder().decode(Set<Date>.self, from: savedData)) == nil)
    }

    @Test("invalid persisted supplement day identities are dropped and not resurrected")
    func invalidPersistedSupplementDaysAreDropped() throws {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let validDay = LocalDay(date: today)
        let stored = [
            StoredSupplementDay(year: validDay.year, month: validDay.month, day: validDay.day),
            StoredSupplementDay(year: validDay.year, month: 13, day: 40),
        ]
        defaults.set(try JSONEncoder().encode(stored), forKey: "dailySupplementTakenDays")

        let store = DailySupplementStore(defaults: defaults)
        let reloadedStore = DailySupplementStore(defaults: defaults)
        let savedData = try #require(defaults.data(forKey: "dailySupplementTakenDays"))
        let savedDays = try JSONDecoder().decode(Set<LocalDay>.self, from: savedData)

        #expect(store.isTaken(on: today))
        #expect(reloadedStore.isTaken(on: today))
        #expect(savedDays == [validDay])
    }

    @Test("malformed persisted payload is replaced with empty storage")
    func malformedPersistedPayloadIsRewritten() throws {
        let defaults = makeDefaults("DailySupplementStoreTests")
        defaults.set(Data("not json".utf8), forKey: "dailySupplementTakenDays")

        let store = DailySupplementStore(defaults: defaults)
        let savedData = try #require(defaults.data(forKey: "dailySupplementTakenDays"))
        let savedDays = try JSONDecoder().decode(Set<LocalDay>.self, from: savedData)

        #expect(!store.isTakenToday)
        #expect(savedDays.isEmpty)
    }

    private struct StoredSupplementDay: Codable {
        let year: Int
        let month: Int
        let day: Int
    }
}
