import Foundation

enum HistoryRetention {
    static func earliestMonth(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(
            byAdding: .month,
            value: -2,
            to: calendar.startOfMonth(for: now)
        )!
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)!.start
    }
}
