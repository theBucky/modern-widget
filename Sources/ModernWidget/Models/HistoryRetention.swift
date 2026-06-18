import Foundation

enum HistoryRetention {
    private static let retainedMonthCount = 3

    static func earliestMonth(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(
            byAdding: .month,
            value: -(retainedMonthCount - 1),
            to: calendar.dateInterval(of: .month, for: now)!.start
        )!
    }
}
