import Darwin
import Foundation

/// Single-pass reader that pulls a handful of scalar fields out of one JSONL line
/// while skipping everything else as opaque byte spans. The coding-usage logs bury a
/// few token counts inside megabytes of thinking text, base64 signatures, and rate
/// limit blocks; tokenizing that bulk (as `JSONSerialization`/`JSONDecoder` do) is the
/// dominant cost, so the scanner steps over unwanted strings, arrays, and objects
/// without allocating them.
///
/// ponytail: assumes well-formed JSONL from the agent tools; malformed input yields a
/// partial extraction that the per-agent guards reject rather than a hard error.
struct JSONScanner {
    private let base: UnsafePointer<UInt8>
    private let count: Int
    private var index: Int = 0

    init?(_ buffer: UnsafeRawBufferPointer) {
        guard let base = buffer.baseAddress, !buffer.isEmpty else {
            return nil
        }
        self.base = base.assumingMemoryBound(to: UInt8.self)
        self.count = buffer.count
    }

    /// Consumes a leading `{`. Returns `false` (after skipping the value) when the next
    /// value is not an object, so callers can descend uniformly.
    mutating func beginObject() -> Bool {
        skipWhitespace()
        guard index < count, base[index] == .openBrace else {
            skipValue()
            return false
        }
        index += 1
        return true
    }

    /// Advances to the next member of the current object, returning its key. Returns
    /// `nil` once the object closes (the closing `}` is consumed). The cursor is left at
    /// the start of the member value, ready for a `read*`/`skipValue`/`beginObject` call.
    mutating func nextKey() -> JSONKey? {
        skipWhitespace()
        guard index < count else { return nil }
        if base[index] == .closeBrace {
            index += 1
            return nil
        }
        if base[index] == .comma {
            index += 1
            skipWhitespace()
            if index < count, base[index] == .closeBrace {
                index += 1
                return nil
            }
        }
        guard index < count, base[index] == .quote else {
            return nil
        }
        let start = index + 1
        skipString()
        let keyEnd = index - 1
        skipWhitespace()
        if index < count, base[index] == .colon {
            index += 1
        }
        return JSONKey(start: base + start, count: keyEnd - start)
    }

    /// Reads an unsigned integer, returning `nil` for fractional, negative, or
    /// overflowing numbers while still consuming the full numeric token.
    mutating func readUInt64() -> UInt64? {
        skipWhitespace()
        var value: UInt64 = 0
        var hasDigits = false
        var invalid = false
        while index < count, base[index].isNumberByte {
            let byte = base[index]
            index += 1
            guard byte >= .zero, byte <= .nine else {
                invalid = true  // a sign, dot, or exponent: not an unsigned integer
                continue
            }
            let (scaled, overflowMul) = value.multipliedReportingOverflow(by: 10)
            let (sum, overflowAdd) = scaled.addingReportingOverflow(UInt64(byte - .zero))
            invalid = invalid || overflowMul || overflowAdd
            value = sum
            hasDigits = true
        }
        return hasDigits && !invalid ? value : nil
    }

    /// Reads any JSON number as a `Double`, consuming the full numeric token.
    mutating func readDouble() -> Double? {
        skipWhitespace()
        let start = index
        while index < count, base[index].isNumberByte {
            index += 1
        }
        guard index > start else { return nil }
        let parsed = String(
            decoding: UnsafeBufferPointer(start: base + start, count: index - start), as: UTF8.self
        ).withCString { strtod($0, nil) }
        return parsed.isFinite ? parsed : nil
    }

    /// Reads a string value, returning `nil` (after skipping) for non-string values.
    mutating func readString() -> String? {
        skipWhitespace()
        guard index < count, base[index] == .quote else {
            skipValue()
            return nil
        }
        let start = index + 1
        var hasEscape = false
        var cursor = start
        while cursor < count {
            let byte = base[cursor]
            if byte == .backslash {
                hasEscape = true
                cursor += 2
                continue
            }
            if byte == .quote { break }
            cursor += 1
        }
        let end = min(cursor, count)
        let bytes = UnsafeBufferPointer(start: base + start, count: end - start)
        index = min(cursor + 1, count)
        if !hasEscape {
            return String(decoding: bytes, as: UTF8.self)
        }
        // Re-quote and let the JSON parser unescape; hand-decoding escapes is error-prone.
        let quoted = Data([.quote]) + Data(buffer: bytes) + Data([.quote])
        return (try? JSONSerialization.jsonObject(with: quoted, options: [.fragmentsAllowed]))
            as? String
    }

    /// Reads a JSON boolean, returning `nil` (after skipping) for non-boolean values.
    mutating func readBool() -> Bool? {
        guard let byte = peekByte() else { return nil }
        skipValue()
        switch byte {
        case .lowerT: return true
        case .lowerF: return false
        default: return nil
        }
    }

    /// Returns the next non-whitespace byte without consuming it.
    mutating func peekByte() -> UInt8? {
        skipWhitespace()
        return index < count ? base[index] : nil
    }

    /// Skips the value at the cursor regardless of type.
    mutating func skipValue() {
        skipWhitespace()
        guard index < count else { return }
        switch base[index] {
        case .quote:
            skipString()
        case .openBrace:
            skipContainer(open: .openBrace, close: .closeBrace)
        case .openBracket:
            skipContainer(open: .openBracket, close: .closeBracket)
        default:
            while index < count, !base[index].endsScalar {
                index += 1
            }
        }
    }

    private mutating func skipWhitespace() {
        while index < count, base[index].isWhitespace {
            index += 1
        }
    }

    /// Skips a string value; assumes the cursor is on the opening quote.
    private mutating func skipString() {
        index += 1
        while index < count {
            switch base[index] {
            case .backslash: index += 2
            case .quote: index += 1; return
            default: index += 1
            }
        }
    }

    /// Skips a balanced container, honoring quoted strings; assumes the cursor is on
    /// the opening bracket.
    private mutating func skipContainer(open: UInt8, close: UInt8) {
        var depth = 0
        while index < count {
            let byte = base[index]
            if byte == .quote {
                skipString()
                continue
            }
            if byte == open {
                depth += 1
            } else if byte == close {
                depth -= 1
                if depth == 0 {
                    index += 1
                    return
                }
            }
            index += 1
        }
    }
}

/// A borrowed view of an object key's raw bytes, compared against ASCII literals.
struct JSONKey {
    let start: UnsafePointer<UInt8>
    let count: Int

    static func == (key: JSONKey, literal: StaticString) -> Bool {
        guard key.count == literal.utf8CodeUnitCount else {
            return false
        }
        return literal.withUTF8Buffer { memcmp(key.start, $0.baseAddress!, key.count) == 0 }
    }
}

extension UInt8 {
    fileprivate static let quote = UInt8(ascii: "\"")
    fileprivate static let backslash = UInt8(ascii: "\\")
    fileprivate static let openBrace = UInt8(ascii: "{")
    fileprivate static let closeBrace = UInt8(ascii: "}")
    fileprivate static let openBracket = UInt8(ascii: "[")
    fileprivate static let closeBracket = UInt8(ascii: "]")
    fileprivate static let comma = UInt8(ascii: ",")
    fileprivate static let colon = UInt8(ascii: ":")
    fileprivate static let zero = UInt8(ascii: "0")
    fileprivate static let nine = UInt8(ascii: "9")
    fileprivate static let lowerT = UInt8(ascii: "t")
    fileprivate static let lowerF = UInt8(ascii: "f")

    fileprivate var isWhitespace: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t") || self == UInt8(ascii: "\n")
            || self == UInt8(ascii: "\r")
    }

    fileprivate var isNumberByte: Bool {
        (self >= .zero && self <= .nine) || self == UInt8(ascii: ".") || self == UInt8(ascii: "e")
            || self == UInt8(ascii: "E") || self == UInt8(ascii: "-") || self == UInt8(ascii: "+")
    }

    /// True at a byte that ends a bare scalar (number/`true`/`false`/`null`).
    fileprivate var endsScalar: Bool {
        self == .comma || self == .closeBrace || self == .closeBracket || isWhitespace
    }
}
