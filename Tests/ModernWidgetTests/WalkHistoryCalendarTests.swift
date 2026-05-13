import Foundation
import Testing

@testable import ModernWidget

@Suite("Walk history calendar")
struct WalkHistoryCalendarTests {
    @Test("month grid uses calendar first weekday")
    func monthGridUsesFirstWeekday() {
        let calendar = gregorianUTC(firstWeekday: 2)
        let month = WalkHistoryMonth(containing: date(2026, 5, 13), calendar: calendar)

        #expect(month.month == date(2026, 5, 1))
        #expect(month.dayCells.count == 35)
        #expect(month.dayCells.prefix(4).allSatisfy { $0 == nil })
        #expect(month.dayCells[4] == date(2026, 5, 1))
        #expect(month.dayCells[34] == date(2026, 5, 31))
    }

    @Test("retention keeps current and two previous months")
    func earliestRetainedMonth() {
        let calendar = gregorianUTC()

        #expect(
            WalkHistoryCalendar.earliestRetainedMonth(
                now: date(2026, 5, 13),
                calendar: calendar
            ) == date(2026, 3, 1)
        )
    }
}
