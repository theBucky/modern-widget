import Foundation

struct CodingUsageDateScope: Equatable, Sendable {
    let now: Date
    let history: DateInterval
    let historyDays: [Date]

    private let calendar: Calendar

    init(now: Date = .now, calendar: Calendar = .current) {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let historyStart = calendar.date(
            byAdding: .day, value: -(Self.historyDayCount - 1), to: todayStart)!

        self.now = now
        self.calendar = calendar
        self.history = DateInterval(start: historyStart, end: tomorrowStart)
        self.historyDays = (0..<Self.historyDayCount).map {
            calendar.date(byAdding: .day, value: $0, to: historyStart)!
        }
    }

    func historyDay(containing date: Date) -> Date? {
        guard date >= history.start && date < history.end else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    /// The windows the usage table totals over. The scope is the single type that
    /// maps a period name to the dates it covers, so callers never redo the math.
    var today: DateInterval { interval(fromDayOffset: 0, toDayOffset: 1) }
    var yesterday: DateInterval { interval(fromDayOffset: -1, toDayOffset: 0) }
    var last7Days: DateInterval { interval(fromDayOffset: -6, toDayOffset: 1) }
    /// The last-30-days row is exactly the rolling scan window.
    var last30Days: DateInterval { history }

    private func interval(fromDayOffset startOffset: Int, toDayOffset endOffset: Int)
        -> DateInterval
    {
        DateInterval(start: day(startOffset), end: day(endOffset))
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    /// Rolling window covering today and the preceding 29 days.
    static let historyDayCount = 30
}
