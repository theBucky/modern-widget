import Darwin
import Foundation

/// Parses the timestamp formats the agent logs emit: UTC ISO-8601 strings (the common
/// case, handled by a `strptime` fast path), offset/ISO variants via `ISO8601DateFormatter`,
/// and numeric epoch seconds/milliseconds.
enum LogTimestamp {
    /// Parses a textual timestamp, retrying on a whitespace-trimmed copy.
    static func parse(_ value: String) -> Date? {
        if let date = parseString(value) {
            return date
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == value ? nil : parseString(trimmed)
    }

    /// Interprets a numeric timestamp, treating large magnitudes as milliseconds.
    static func fromEpoch(_ raw: Double) -> Date {
        raw > 10_000_000_000
            ? Date(timeIntervalSince1970: raw / 1_000)
            : Date(timeIntervalSince1970: raw)
    }

    private static func parseString(_ value: String) -> Date? {
        if let date = parseUTC(value) {
            return date
        }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) {
            return date
        }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }

    private static func parseUTC(_ value: String) -> Date? {
        value.withCString { valuePointer in
            var components = Darwin.tm()
            guard let end = strptime(valuePointer, "%Y-%m-%dT%H:%M:%S", &components),
                let fractionalSeconds = fractionalSeconds(after: end)
            else {
                return nil
            }
            let seconds = timegm(&components)
            return Date(timeIntervalSince1970: TimeInterval(seconds) + fractionalSeconds)
        }
    }

    private static func fractionalSeconds(after pointer: UnsafePointer<CChar>) -> TimeInterval? {
        let dot = CChar(UInt8(ascii: "."))
        let z = CChar(UInt8(ascii: "Z"))
        if pointer.pointee == z {
            return pointer.successor().pointee == 0 ? 0 : nil
        }
        guard pointer.pointee == dot else {
            return nil
        }

        var cursor = pointer.successor()
        var fraction = 0.0
        var divisor = 10.0
        while cursor.pointee >= CChar(UInt8(ascii: "0"))
            && cursor.pointee <= CChar(UInt8(ascii: "9"))
        {
            if divisor <= 1_000_000_000 {
                fraction += Double(cursor.pointee - CChar(UInt8(ascii: "0"))) / divisor
                divisor *= 10
            }
            cursor = cursor.successor()
        }
        guard cursor > pointer.successor(), cursor.pointee == z, cursor.successor().pointee == 0
        else {
            return nil
        }
        return fraction
    }
}

extension JSONScanner {
    /// Reads a timestamp value, accepting either a textual or numeric encoding.
    mutating func readTimestamp() -> Date? {
        guard let byte = peekByte() else {
            return nil
        }
        if byte == 0x22 {
            return readString().flatMap(LogTimestamp.parse)
        }
        return readDouble().map(LogTimestamp.fromEpoch)
    }
}
