import Darwin
import Foundation

/// Single-pass reader that pulls a handful of scalar fields out of one JSONL line
/// while skipping everything else as opaque byte spans. The coding-usage logs bury a
/// few token counts inside megabytes of thinking text, base64 signatures, and rate
/// limit blocks; tokenizing that bulk (as `JSONSerialization`/`JSONDecoder` do) is the
/// dominant cost, so the scanner steps over unwanted strings, arrays, and objects
/// without allocating them.
///
/// Assumes well-formed JSONL from the agent tools; malformed input yields a partial
/// extraction that the per-agent guards reject rather than a hard error.
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
        guard let key = consumeStringPayload() else {
            return nil
        }
        skipWhitespace()
        if index < count, base[index] == .colon {
            index += 1
        }
        return JSONKey(start: key.start, count: key.count)
    }

    /// Reads an unsigned integer. Returns `nil` for fractional, negative, overflowing,
    /// or non-numeric values, consuming the whole value either way so a malformed field
    /// never swallows the sibling fields that follow it.
    mutating func readUInt64() -> UInt64? {
        skipWhitespace()
        guard index < count, base[index].isDigit else {
            skipValue()
            return nil
        }

        var value: UInt64 = 0
        var overflow = false
        while index < count, base[index].isDigit {
            let (scaled, overflowMul) = value.multipliedReportingOverflow(by: 10)
            let (sum, overflowAdd) = scaled.addingReportingOverflow(UInt64(base[index] - .zero))
            overflow = overflow || overflowMul || overflowAdd
            value = sum
            index += 1
        }

        guard index == count || !base[index].isNumberByte else {
            skipValue()
            return nil
        }
        return overflow ? nil : value
    }

    /// Reads a finite JSON number. JSON delimiters terminate `strtod` before it can
    /// leave the borrowed line buffer, avoiding a String allocation per currency value.
    mutating func readDouble() -> Double? {
        skipWhitespace()
        let scalar = consumeScalar()
        guard scalar.count > 0 else {
            return nil
        }
        if index == count {
            let bytes = UnsafeBufferPointer(start: scalar.start, count: scalar.count)
            guard let value = Double(String(decoding: bytes, as: UTF8.self)), value.isFinite else {
                return nil
            }
            return value
        }
        let start = UnsafeRawPointer(scalar.start).assumingMemoryBound(to: CChar.self)
        var end: UnsafeMutablePointer<CChar>?
        let value = strtod(start, &end)
        guard let end, end == start + scalar.count, value.isFinite else {
            return nil
        }
        return value
    }

    /// Reads a string value, returning `nil` (after skipping) for non-string values.
    mutating func readString() -> String? {
        readStringValue()?.string
    }

    /// Reads a string and compares it to an ASCII literal without allocating on the
    /// common unescaped path.
    mutating func readStringEquals(_ literal: StaticString) -> Bool {
        readStringValue()?.equals(literal) == true
    }

    /// Reads a borrowed string value, returning `nil` (after skipping) for non-strings.
    mutating func readStringValue() -> JSONStringValue? {
        skipWhitespace()
        guard let value = consumeStringPayload() else {
            skipValue()
            return nil
        }
        return value
    }

    /// Reads a JSON boolean, returning `nil` (after skipping) for non-boolean values.
    mutating func readBool() -> Bool? {
        skipWhitespace()
        guard index < count else { return nil }
        switch base[index] {
        case .lowerT:
            return readBareScalar(equals: "true") ? true : nil
        case .lowerF:
            return readBareScalar(equals: "false") ? false : nil
        default:
            skipValue()
            return nil
        }
    }

    /// Skips the value at the cursor regardless of type.
    mutating func skipValue() {
        skipWhitespace()
        guard index < count else { return }

        switch base[index] {
        case .quote:
            skipStringPayload()
        case .openBrace, .openBracket:
            consumeContainer()
        default:
            _ = consumeScalar()
        }
    }

    private mutating func skipWhitespace() {
        while index < count, base[index].isWhitespace {
            index += 1
        }
    }

    private mutating func readBareScalar(equals literal: StaticString) -> Bool {
        let scalar = consumeScalar()
        let scalarCount = scalar.count
        return scalarCount == literal.utf8CodeUnitCount
            && memcmp(scalar.start, literal.utf8Start, scalarCount) == 0
    }

    private mutating func consumeScalar() -> (start: UnsafePointer<UInt8>, count: Int) {
        let start = index
        while index < count, !base[index].endsScalar {
            index += 1
        }
        return (base + start, index - start)
    }

    /// Consumes a quoted JSON string and returns its payload without the quotes.
    private mutating func consumeStringPayload() -> JSONStringValue? {
        guard index < count, base[index] == .quote else {
            return nil
        }

        let start = index + 1
        var cursor = start
        var hasEscape = false

        while cursor < count {
            let byte = base[cursor]
            if byte == .backslash {
                hasEscape = true
                cursor += 2
                continue
            }
            if byte == .quote {
                let value = JSONStringValue(
                    start: base + start,
                    count: cursor - start,
                    hasEscape: hasEscape
                )
                index = cursor + 1
                return value
            }
            cursor += 1
        }

        index = count
        return JSONStringValue(start: base + start, count: count - start, hasEscape: hasEscape)
    }

    /// Skips a quoted string on the discard path without materializing its payload,
    /// jumping quote-to-quote with `memchr` instead of walking every byte. Megabytes of
    /// thinking text and base64 between the token counts dominate the scan, and SIMD
    /// `memchr` clears them far faster than a per-byte loop. A quote terminates only when
    /// preceded by an even backslash run; the read path keeps `consumeStringPayload` so it
    /// can still report `hasEscape`. The cursor lands past the closing quote, or at the end
    /// for an unterminated string.
    private mutating func skipStringPayload() {
        var cursor = index + 1
        while cursor < count,
            let hit = memchr(base + cursor, Int32(UInt8.quote), count - cursor)
        {
            let quoteIndex = UnsafeRawPointer(hit) - UnsafeRawPointer(base)
            var escaped = false
            var scan = quoteIndex - 1
            while scan >= cursor, base[scan] == .backslash {
                escaped.toggle()
                scan -= 1
            }
            if !escaped {
                index = quoteIndex + 1
                return
            }
            cursor = quoteIndex + 1
        }
        index = count
    }

    /// Consumes the object or array at the cursor, honoring nested containers and strings.
    private mutating func consumeContainer() {
        var depth = 1
        index += 1

        while index < count {
            switch base[index] {
            case .quote:
                skipStringPayload()
            case .openBrace, .openBracket:
                depth += 1
                index += 1
            case .closeBrace, .closeBracket:
                depth -= 1
                index += 1
                if depth == 0 {
                    return
                }
            default:
                index += 1
            }
        }
    }
}

struct JSONLineNeedle {
    fileprivate let bytes: UnsafeRawPointer
    fileprivate let byteCount: Int

    init(_ literal: StaticString) {
        precondition(literal.hasPointerRepresentation && literal.utf8CodeUnitCount > 0)
        bytes = UnsafeRawPointer(literal.utf8Start)
        byteCount = literal.utf8CodeUnitCount
    }
}

extension UnsafeRawBufferPointer {
    /// Reports whether `needle` occurs in the buffer, via `memmem`.
    func contains(_ needle: JSONLineNeedle) -> Bool {
        guard let base = baseAddress, count >= needle.byteCount else {
            return false
        }
        return memmem(base, count, needle.bytes, needle.byteCount) != nil
    }
}

/// A borrowed JSON string payload, excluding the surrounding quotes.
struct JSONStringValue {
    let start: UnsafePointer<UInt8>
    let count: Int
    let hasEscape: Bool

    var string: String? {
        let bytes = UnsafeBufferPointer(start: start, count: count)
        if !hasEscape {
            return String(decoding: bytes, as: UTF8.self)
        }
        let quoted = Data([.quote]) + Data(buffer: bytes) + Data([.quote])
        return (try? JSONSerialization.jsonObject(with: quoted, options: [.fragmentsAllowed]))
            as? String
    }

    /// Compact identity for cached dedupe records; avoids retaining two allocated ID
    /// strings for every Claude message in the active history window.
    var fnv1a64: UInt64 {
        if hasEscape, let string {
            return Self.fnv1a64(of: string.utf8)
        }
        return Self.fnv1a64(of: UnsafeBufferPointer(start: start, count: count))
    }

    private static func fnv1a64(of bytes: some Sequence<UInt8>) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return hash
    }

    func equals(_ literal: StaticString) -> Bool {
        literal.withUTF8Buffer { literalBytes in
            if !hasEscape {
                return count == literalBytes.count
                    && memcmp(start, literalBytes.baseAddress!, count) == 0
            }
            guard let string else { return false }
            return string == String(decoding: literalBytes, as: UTF8.self)
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
    fileprivate static let dot = UInt8(ascii: ".")
    fileprivate static let plus = UInt8(ascii: "+")
    fileprivate static let minus = UInt8(ascii: "-")
    fileprivate static let zero = UInt8(ascii: "0")
    fileprivate static let nine = UInt8(ascii: "9")
    fileprivate static let lowerE = UInt8(ascii: "e")
    fileprivate static let upperE = UInt8(ascii: "E")
    fileprivate static let lowerT = UInt8(ascii: "t")
    fileprivate static let lowerF = UInt8(ascii: "f")

    fileprivate var isWhitespace: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t") || self == UInt8(ascii: "\n")
            || self == UInt8(ascii: "\r")
    }

    fileprivate var isDigit: Bool {
        self >= .zero && self <= .nine
    }

    fileprivate var isNumberByte: Bool {
        isDigit || self == .dot || self == .lowerE || self == .upperE || self == .minus
            || self == .plus
    }

    /// True at a byte that ends a bare scalar (number/`true`/`false`/`null`).
    fileprivate var endsScalar: Bool {
        self == .comma || self == .closeBrace || self == .closeBracket || isWhitespace
    }
}
