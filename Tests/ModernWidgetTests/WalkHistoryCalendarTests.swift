import Foundation
import Testing

@testable import ModernWidget

@Suite("Walk history calendar")
struct WalkHistoryCalendarTests {
    @Test("month exposes every day in order")
    func monthExposesEveryDayInOrder() {
        let calendar = gregorianUTC(firstWeekday: 2)
        let firstDay = date(2026, 5, 1)
        let month = WalkHistoryMonth(containing: date(2026, 5, 13), calendar: calendar)
        let expectedDays = (0..<31).map { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: firstDay)!
        }

        #expect(month.month == firstDay)
        #expect(month.dayCells.compactMap { $0 } == expectedDays)
    }

    @Test("month start aligns with the calendar first weekday")
    func monthStartAlignsWithCalendarFirstWeekday() throws {
        let calendar = gregorianUTC(firstWeekday: 2)
        let firstDay = date(2026, 5, 1)
        let month = WalkHistoryMonth(containing: date(2026, 5, 13), calendar: calendar)
        let firstDayIndex = try #require(month.dayCells.firstIndex(of: firstDay))
        let actualColumn = firstDayIndex % 7
        let expectedColumn =
            (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7

        #expect(actualColumn == expectedColumn)
    }

    @Test("weekday symbols follow calendar first weekday")
    func weekdaySymbolsFollowFirstWeekday() {
        let calendar = gregorianUTC(firstWeekday: 2)

        #expect(
            WalkHistoryCalendar.weekdaySymbols(calendar: calendar)
                == ["M", "T", "W", "T", "F", "S", "S"]
        )
    }
}
