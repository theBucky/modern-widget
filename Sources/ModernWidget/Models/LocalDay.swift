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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)
        guard let validDay = LocalDay(year: year, month: month, day: day) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "invalid Gregorian local day \(year)-\(month)-\(day)"
                )
            )
        }
        self = validDay
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private enum CodingKeys: String, CodingKey {
        case year, month, day
    }

    /// Gregorian calendar in the current time zone; defines local-day boundaries.
    /// Carries the current locale so presentation derived from it (weekday order,
    /// symbols) matches the user while day identity stays Gregorian.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.locale = .autoupdatingCurrent
        return calendar
    }()
}
