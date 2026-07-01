import Foundation

enum HistoryRetention {
    static func currentMonth(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.startOfMonth(for: now)
    }

    static func earliestMonth(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: -2, to: currentMonth(now: now, calendar: calendar))!
    }

    static func earliestRetainedDay(now: Date = .now) -> LocalDay {
        LocalDay(date: earliestMonth(now: now, calendar: LocalDay.calendar))
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)!.start
    }
}
