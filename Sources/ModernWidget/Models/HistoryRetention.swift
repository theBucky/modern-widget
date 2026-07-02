import Foundation

enum HistoryRetention {
    /// The current month plus the two before it. `LocalDay.calendar` is the single
    /// authority for every retention and day-identity computation, matching the stores.
    static let retainedMonthCount = 3

    static func currentMonth(now: Date = .now, calendar: Calendar = LocalDay.calendar) -> Date {
        calendar.startOfMonth(for: now)
    }

    static func earliestMonth(now: Date = .now, calendar: Calendar = LocalDay.calendar) -> Date {
        calendar.date(
            byAdding: .month,
            value: -(retainedMonthCount - 1),
            to: currentMonth(now: now, calendar: calendar)
        )!
    }

    static func earliestRetainedDay(now: Date = .now) -> LocalDay {
        LocalDay(date: earliestMonth(now: now))
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)!.start
    }
}
