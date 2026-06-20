import Foundation

enum HistoryRetention {
    private static let retainedMonthCount = 3

    static func earliestMonth(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(
            byAdding: .month,
            value: -(retainedMonthCount - 1),
            to: calendar.startOfMonth(for: now)
        )!
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)!.start
    }
}
