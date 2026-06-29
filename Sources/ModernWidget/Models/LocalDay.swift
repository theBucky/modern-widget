import Foundation

struct LocalDay: Comparable, Hashable, Codable {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date) {
        let components = Self.calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year!
        self.month = components.month!
        self.day = components.day!
    }

    init?(year: Int, month: Int, day: Int) {
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: Self.calendar) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}
