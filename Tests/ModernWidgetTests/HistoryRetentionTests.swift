import Foundation
import Testing

@testable import ModernWidget

@Suite("history retention")
struct HistoryRetentionTests {
    @Test("retention keeps current and two previous months")
    func earliestMonth() {
        let calendar = gregorianUTC()

        #expect(
            HistoryRetention.earliestMonth(
                now: date(2026, 5, 13),
                calendar: calendar
            ) == date(2026, 3, 1)
        )
    }

    @Test("retention crosses year boundary")
    func earliestMonthCrossesYearBoundary() {
        let calendar = gregorianUTC()

        #expect(
            HistoryRetention.earliestMonth(
                now: date(2026, 1, 13),
                calendar: calendar
            ) == date(2025, 11, 1)
        )
    }
}
