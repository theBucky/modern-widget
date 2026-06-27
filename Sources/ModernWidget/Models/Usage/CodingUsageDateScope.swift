import Foundation

struct CodingUsageDateScope: Equatable, Sendable {
    let now: Date
    let history: DateInterval
    let historyDays: [Date]

    private let calendar: Calendar

    init(now: Date = .now, calendar: Calendar = .current) {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let rollingStart = calendar.date(byAdding: .day, value: -29, to: todayStart)!
        let monthStart = calendar.dateInterval(of: .month, for: now)!.start
        let historyStart = min(rollingStart, monthStart)
        let dayCount = calendar.dateComponents([.day], from: historyStart, to: tomorrowStart).day!

        self.now = now
        self.calendar = calendar
        self.history = DateInterval(start: historyStart, end: tomorrowStart)
        self.historyDays = (0..<dayCount).map {
            calendar.date(byAdding: .day, value: $0, to: historyStart)!
        }
    }

    func historyDay(containing date: Date) -> Date? {
        guard date >= history.start && date < history.end else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }
}
