import Foundation

struct WalkHistoryMonth: Equatable {
    let month: Date
    let dayCells: [Date?]

    init(containing date: Date, calendar: Calendar = .current) {
        let firstDay = WalkHistoryCalendar.startOfMonth(date, calendar: calendar)
        let dayCount = calendar.range(of: .day, in: .month, for: firstDay)!.count
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let leadingDays = Array<Date?>(repeating: nil, count: leadingBlanks)
        let days: [Date?] = (0..<dayCount).map {
            calendar.date(byAdding: .day, value: $0, to: firstDay)
        }
        let trailingDays = Array<Date?>(
            repeating: nil,
            count: (7 - (leadingDays.count + days.count) % 7) % 7
        )

        month = firstDay
        dayCells = leadingDays + days + trailingDays
    }
}

enum WalkHistoryCalendar {
    private static let retentionMonths = 3

    static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    static func earliestRetainedMonth(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(
            byAdding: .month,
            value: -(retentionMonths - 1),
            to: startOfMonth(now, calendar: calendar)
        )!
    }

    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }
}
