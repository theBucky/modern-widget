import Foundation

/// Parses the canonical timestamp formats the agent logs emit: UTC ISO-8601 strings
/// and numeric epoch seconds/milliseconds.
enum LogTimestamp {
    /// Parses a textual timestamp.
    static func parse(_ value: String) -> Date? {
        let count = value.utf8.count
        return value.withCString {
            parseUTC(
                start: UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self),
                count: count
            )
        }
    }

    /// Interprets a numeric timestamp, treating large magnitudes as milliseconds.
    static func fromEpoch(_ raw: Double) -> Date {
        raw > 10_000_000_000
            ? Date(timeIntervalSince1970: raw / 1_000)
            : Date(timeIntervalSince1970: raw)
    }

    /// Parses a borrowed JSON string timestamp without allocating.
    static func parse(_ value: JSONStringValue) -> Date? {
        if value.hasEscape {
            return nil
        }
        return parseUTC(start: value.start, count: value.count)
    }

    private static func parseUTC(start: UnsafePointer<UInt8>, count: Int) -> Date? {
        guard count >= 20 else {
            return nil
        }

        guard start[4] == .dash, start[7] == .dash, start[10] == .upperT,
            start[13] == .colon, start[16] == .colon,
            let year = digits(start, 0, 4),
            let month = digits(start, 5, 2),
            let day = digits(start, 8, 2),
            let hour = digits(start, 11, 2),
            let minute = digits(start, 14, 2),
            let second = digits(start, 17, 2),
            month >= 1, month <= 12,
            day >= 1, day <= 31,
            hour <= 23,
            minute <= 59,
            second <= 60
        else {
            return nil
        }

        var offset = 19
        var fraction = 0.0
        if start[offset] == .dot {
            offset += 1
            let fractionStart = offset
            var divisor = 10.0
            while offset < count, start[offset] >= .zero, start[offset] <= .nine {
                if divisor <= 1_000_000_000 {
                    fraction += Double(start[offset] - .zero) / divisor
                    divisor *= 10
                }
                offset += 1
            }
            guard offset > fractionStart else {
                return nil
            }
        }

        guard offset + 1 == count, start[offset] == .upperZ else {
            return nil
        }

        guard
            let seconds = epochSeconds(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
        else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(seconds) + fraction)
    }

    private static func digits(_ start: UnsafePointer<UInt8>, _ offset: Int, _ count: Int)
        -> Int?
    {
        var value = 0
        for index in offset..<(offset + count) {
            guard start[index] >= .zero, start[index] <= .nine else {
                return nil
            }
            value = value * 10 + Int(start[index] - .zero)
        }
        return value
    }

    private static func epochSeconds(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int
    ) -> Int64? {
        guard day <= daysInMonth(month: month, year: year) else {
            return nil
        }

        let adjustedYear = year - (month <= 2 ? 1 : 0)
        let era = adjustedYear >= 0 ? adjustedYear / 400 : (adjustedYear - 399) / 400
        let yearOfEra = adjustedYear - era * 400
        let monthPrime = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * monthPrime + 2) / 5 + day - 1
        let dayOfEra =
            yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = Int64(era * 146_097 + dayOfEra - 719_468)
        return days * 86_400 + Int64(hour * 3_600 + minute * 60 + second)
    }

    private static func daysInMonth(month: Int, year: Int) -> Int {
        switch month {
        case 2:
            return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    }

}

extension JSONScanner {
    /// Reads a timestamp value, accepting either a textual or numeric encoding.
    mutating func readTimestamp() -> Date? {
        guard let byte = peekByte() else {
            return nil
        }
        if byte == 0x22 {
            return readStringValue().flatMap(LogTimestamp.parse)
        }
        return readDouble().map(LogTimestamp.fromEpoch)
    }
}

extension UInt8 {
    fileprivate static let dash = UInt8(ascii: "-")
    fileprivate static let dot = UInt8(ascii: ".")
    fileprivate static let colon = UInt8(ascii: ":")
    fileprivate static let upperT = UInt8(ascii: "T")
    fileprivate static let upperZ = UInt8(ascii: "Z")
    fileprivate static let zero = UInt8(ascii: "0")
    fileprivate static let nine = UInt8(ascii: "9")
}
