import Foundation
import Testing

@testable import ModernWidget

@MainActor
@Suite("Daily supplement store")
struct DailySupplementStoreTests {
    @Test("taken status is stored per calendar day")
    func takenStatusIsStoredPerCalendarDay() {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let now = date(2026, 6, 18, 12)
        let store = DailySupplementStore(defaults: defaults, now: now)
        let calendar = LocalDay.calendar
        let today = calendar.startOfDay(for: now)
        let morning = calendar.date(byAdding: .hour, value: 8, to: today)!
        let evening = calendar.date(byAdding: .hour, value: 21, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        store.setTaken(true, on: evening, now: now)

        let reloadedStore = DailySupplementStore(defaults: defaults, now: now)
        #expect(reloadedStore.isTaken(on: morning))
        #expect(reloadedStore.isTaken(on: evening))
        #expect(!reloadedStore.isTaken(on: tomorrow))
    }

    @Test("clearing one day leaves other days alone")
    func clearingOneDayLeavesOtherDaysAlone() {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let now = date(2026, 6, 18, 12)
        let store = DailySupplementStore(defaults: defaults, now: now)
        let calendar = LocalDay.calendar
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        store.setTaken(true, on: today, now: now)
        store.setTaken(true, on: tomorrow, now: now)
        store.setTaken(false, on: today, now: now)

        #expect(!store.isTaken(on: today))
        #expect(store.isTaken(on: tomorrow))
    }

    @Test("days outside the retention window are ignored")
    func daysOutsideRetentionWindowAreIgnored() {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let now = date(2026, 6, 18, 12)
        let store = DailySupplementStore(defaults: defaults, now: now)
        let calendar = LocalDay.calendar
        let today = calendar.startOfDay(for: now)
        let expiredDay = calendar.date(byAdding: .month, value: -4, to: today)!

        store.setTaken(true, on: expiredDay, now: now)
        store.setTaken(true, on: today, now: now)

        let reloadedStore = DailySupplementStore(defaults: defaults, now: now)
        #expect(!reloadedStore.isTaken(on: expiredDay))
        #expect(reloadedStore.isTaken(on: today))
    }

    @Test("loading prunes expired persisted days")
    func loadingPrunesExpiredPersistedDays() throws {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let now = date(2026, 6, 18, 12)
        let calendar = LocalDay.calendar
        let today = calendar.startOfDay(for: now)
        let expiredDay = calendar.date(byAdding: .month, value: -4, to: today)!
        let stored = [expiredDay, today].map { day -> StoredSupplementDay in
            let localDay = LocalDay(date: day)
            return StoredSupplementDay(
                year: localDay.year, month: localDay.month, day: localDay.day)
        }

        defaults.set(
            try JSONEncoder().encode(stored),
            forKey: "dailySupplementTakenDays"
        )

        _ = DailySupplementStore(defaults: defaults, now: now)
        let reloadedStore = DailySupplementStore(defaults: defaults, now: now)

        #expect(reloadedStore.isTaken(on: today))
        #expect(!reloadedStore.isTaken(on: expiredDay))
        let savedData = try #require(defaults.data(forKey: "dailySupplementTakenDays"))
        let savedDays = try JSONDecoder().decode(Set<LocalDay>.self, from: savedData)
        #expect(savedDays == [LocalDay(date: today)])
    }

    @Test("invalid persisted supplement day identities are dropped and not resurrected")
    func invalidPersistedSupplementDaysAreDropped() throws {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let now = date(2026, 6, 18, 12)
        let calendar = LocalDay.calendar
        let today = calendar.startOfDay(for: now)
        let validDay = LocalDay(date: today)
        let stored = [
            StoredSupplementDay(year: validDay.year, month: validDay.month, day: validDay.day),
            StoredSupplementDay(year: validDay.year, month: 13, day: 40),
        ]
        defaults.set(try JSONEncoder().encode(stored), forKey: "dailySupplementTakenDays")

        let store = DailySupplementStore(defaults: defaults, now: now)
        let reloadedStore = DailySupplementStore(defaults: defaults, now: now)
        let savedData = try #require(defaults.data(forKey: "dailySupplementTakenDays"))
        let savedDays = try JSONDecoder().decode(Set<LocalDay>.self, from: savedData)

        #expect(store.isTaken(on: today))
        #expect(reloadedStore.isTaken(on: today))
        #expect(savedDays == [validDay])
    }

    @Test("malformed persisted payload is replaced with empty storage")
    func malformedPersistedPayloadIsRewritten() throws {
        let defaults = makeDefaults("DailySupplementStoreTests")
        let now = date(2026, 6, 18, 12)
        defaults.set(Data("not json".utf8), forKey: "dailySupplementTakenDays")

        let store = DailySupplementStore(defaults: defaults, now: now)
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
