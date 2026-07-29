import Foundation
import Testing

@testable import ModernWidget

@Suite("Walk history calendar")
struct WalkHistoryCalendarTests {
    @Test("month exposes every day in order")
    func monthExposesEveryDayInOrder() {
        let calendar = gregorianUTC(firstWeekday: 2)
        let month = WalkHistoryMonth(containing: date(2026, 5, 13), calendar: calendar)
        let expectedDays = (1...31).map { LocalDay(year: 2026, month: 5, day: $0)! }

        #expect(month.month == date(2026, 5, 1))
        #expect(month.dayCells.compactMap(\.day) == expectedDays)
    }

    @Test("month start aligns with the calendar first weekday")
    func monthStartAlignsWithCalendarFirstWeekday() throws {
        let calendar = gregorianUTC(firstWeekday: 2)
        let firstDay = LocalDay(year: 2026, month: 5, day: 1)
        let month = WalkHistoryMonth(containing: date(2026, 5, 13), calendar: calendar)
        let firstDayIndex = try #require(month.dayCells.firstIndex { $0.day == firstDay })
        let actualColumn = firstDayIndex % 7
        let expectedColumn =
            (calendar.component(.weekday, from: date(2026, 5, 1)) - calendar.firstWeekday + 7) % 7

        #expect(actualColumn == expectedColumn)
    }

    @Test("weekday symbols follow calendar first weekday")
    func weekdaySymbolsFollowFirstWeekday() {
        let calendar = gregorianUTC(firstWeekday: 2)

        #expect(
            WalkHistoryMonth.weekdayLabels(calendar: calendar).map(\.symbol)
                == ["M", "T", "W", "T", "F", "S", "S"]
        )
    }
}
