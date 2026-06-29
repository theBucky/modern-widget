import Foundation
import Testing

@testable import ModernWidget

@Suite("Local day")
struct LocalDayTests {
    @Test("different times on the same day map to one canonical local day")
    func sameDayDifferentTimesShareOneLocalDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let morning = calendar.date(byAdding: .hour, value: 9, to: today)!
        let evening = calendar.date(byAdding: .hour, value: 22, to: today)!

        #expect(LocalDay(date: morning) == LocalDay(date: evening))
    }

    @Test("the canonical day is the gregorian year, month, and day in the current time zone")
    func canonicalDayMatchesGregorianComponents() {
        let now = Date.now
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let components = gregorian.dateComponents([.year, .month, .day], from: now)

        let day = LocalDay(date: now)
        #expect(day.year == components.year)
        #expect(day.month == components.month)
        #expect(day.day == components.day)
    }

    @Test("the canonical day ignores the calendar first weekday setting")
    func canonicalDayIgnoresFirstWeekday() {
        let now = Date.now
        var sundayFirst = Calendar(identifier: .gregorian)
        sundayFirst.timeZone = .current
        sundayFirst.firstWeekday = 1
        var thursdayFirst = sundayFirst
        thursdayFirst.firstWeekday = 5

        let day = LocalDay(date: now)
        let sundayComponents = sundayFirst.dateComponents([.year, .month, .day], from: now)
        let thursdayComponents = thursdayFirst.dateComponents([.year, .month, .day], from: now)

        #expect(day.year == sundayComponents.year)
        #expect(day.month == sundayComponents.month)
        #expect(day.day == sundayComponents.day)
        #expect(sundayComponents == thursdayComponents)
    }

    @Test("invalid gregorian components do not form a local day")
    func invalidComponentsProduceNoLocalDay() {
        #expect(LocalDay(year: 2026, month: 13, day: 1) == nil)
        #expect(LocalDay(year: 2026, month: 0, day: 1) == nil)
        #expect(LocalDay(year: 2026, month: 4, day: 31) == nil)
        #expect(LocalDay(year: 2026, month: 2, day: 29) == nil)
        #expect(LocalDay(year: 2024, month: 2, day: 29) != nil)
        #expect(LocalDay(year: 2026, month: 5, day: 13) != nil)
    }
}
