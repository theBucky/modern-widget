import Darwin
import Foundation

/// Single-pass reader that pulls a handful of scalar fields out of one JSONL line
/// while skipping everything else as opaque byte spans. The coding-usage logs bury a
/// few token counts inside megabytes of thinking text, base64 signatures, and rate
/// limit blocks; tokenizing that bulk (as `JSONSerialization`/`JSONDecoder` do) is the
/// dominant cost, so the scanner steps over unwanted strings, arrays, and objects
/// without allocating them.
///
/// Provider parsers finish each relevant document before accepting extracted fields;
/// malformed input is rejected without turning scanner failures into hard errors.
struct JSONScanner {
    private let base: UnsafePointer<UInt8>
    private let count: Int
    private var index: Int = 0
    private var objectDepth = 0
    private var objectNeedsSeparator: UInt64 = 0
    private var isValid = true

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
        guard objectDepth < UInt64.bitWidth else {
            isValid = false
            index = count
            return false
        }
        let mask = UInt64(1) << objectDepth
        objectNeedsSeparator &= ~mask
        objectDepth += 1
        index += 1
        return true
    }

    /// Advances to the next member of the current object, returning its key. Returns
    /// `nil` once the object closes (the closing `}` is consumed). The cursor is left at
    /// the start of the member value, ready for a `read*`/`skipValue`/`beginObject` call.
    mutating func nextKey() -> JSONKey? {
        guard objectDepth > 0 else {
            isValid = false
            return nil
        }
        skipWhitespace()
        guard index < count else {
            isValid = false
            return nil
        }

        if base[index] == .closeBrace {
            index += 1
            closeObject()
            return nil
        }

        let mask = UInt64(1) << (objectDepth - 1)
        if objectNeedsSeparator & mask != 0 {
            guard base[index] == .comma else {
                isValid = false
                return nil
            }
            index += 1
            skipWhitespace()
            if index < count, base[index] == .closeBrace {
                isValid = false
                index += 1
                closeObject()
                return nil
            }
        } else if base[index] == .comma {
            isValid = false
            return nil
        }
        guard let key = consumeStringPayload() else {
            isValid = false
            return nil
        }
        skipWhitespace()
        guard index < count, base[index] == .colon else {
            isValid = false
            return nil
        }
        index += 1
        objectNeedsSeparator |= mask
        return JSONKey(start: key.start, count: key.count)
    }

    /// Returns `true` only after every entered object closed and no trailing bytes remain.
    mutating func finishDocument() -> Bool {
        skipWhitespace()
        return isValid && objectDepth == 0 && index == count
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

        let start = index
        var value: UInt64 = 0
        var overflow = false
        while index < count, base[index].isDigit {
            let (scaled, overflowMul) = value.multipliedReportingOverflow(by: 10)
            let (sum, overflowAdd) = scaled.addingReportingOverflow(UInt64(base[index] - .zero))
            overflow = overflow || overflowMul || overflowAdd
            value = sum
            index += 1
        }

        guard !(base[start] == .zero && index - start > 1),
            index == count || !base[index].isNumberByte
        else {
            skipValue()
            return nil
        }
        return overflow ? nil : value
    }

    /// Reads a finite JSON number using Swift's locale-independent parser.
    mutating func readDouble() -> Double? {
        skipWhitespace()
        let scalar = consumeScalar()
        guard isValidJSONNumber(scalar) else {
            return nil
        }
        let bytes = UnsafeBufferPointer(start: scalar.start, count: scalar.count)
        guard let value = Double(String(decoding: bytes, as: UTF8.self)), value.isFinite else {
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
        if !consumeValue(depth: 0) {
            isValid = false
        }
    }

    private mutating func skipWhitespace() {
        while index < count, base[index].isWhitespace {
            index += 1
        }
    }

    private mutating func closeObject() {
        objectDepth -= 1
        objectNeedsSeparator &= ~(UInt64(1) << objectDepth)
    }

    private mutating func readBareScalar(equals literal: StaticString) -> Bool {
        let scalar = consumeScalar()
        return matches(literal, scalar: scalar)
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
                guard cursor + 1 < count else {
                    isValid = false
                    index = count
                    return nil
                }
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

        isValid = false
        index = count
        return nil
    }

    /// Skips a quoted string on the discard path without materializing its payload,
    /// jumping quote-to-quote with `memchr` instead of walking every byte. Megabytes of
    /// thinking text and base64 between the token counts dominate the scan, and SIMD
    /// `memchr` clears them far faster than a per-byte loop. A quote terminates only when
    /// preceded by an even backslash run; the read path keeps `consumeStringPayload` so it
    /// can still report `hasEscape`. The cursor lands past the closing quote, or at the end
    /// for an unterminated string.
    private mutating func skipStringPayload() -> Bool {
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
                return true
            }
            cursor = quoteIndex + 1
        }
        isValid = false
        index = count
        return false
    }

    private mutating func consumeValue(depth: Int) -> Bool {
        skipWhitespace()
        guard index < count, depth < UInt64.bitWidth else {
            return false
        }

        switch base[index] {
        case .quote:
            return skipStringPayload()
        case .openBrace:
            return consumeObjectValue(depth: depth + 1)
        case .openBracket:
            return consumeArray(depth: depth + 1)
        default:
            return isValidJSONScalar(consumeScalar())
        }
    }

    private mutating func consumeObjectValue(depth: Int) -> Bool {
        let startingDepth = objectDepth
        guard depth < UInt64.bitWidth, beginObject() else {
            return false
        }
        while nextKey() != nil {
            guard consumeValue(depth: depth) else {
                isValid = false
                return false
            }
        }
        return isValid && objectDepth == startingDepth
    }

    private mutating func consumeArray(depth: Int) -> Bool {
        index += 1
        skipWhitespace()
        if consume(.closeBracket) {
            return true
        }

        while index < count {
            guard consumeValue(depth: depth) else {
                return false
            }
            skipWhitespace()
            if consume(.closeBracket) {
                return true
            }
            guard consume(.comma) else {
                return false
            }
            skipWhitespace()
        }
        return false
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < count, base[index] == byte else {
            return false
        }
        index += 1
        return true
    }

    private func isValidJSONScalar(
        _ scalar: (start: UnsafePointer<UInt8>, count: Int)
    ) -> Bool {
        matches("true", scalar: scalar)
            || matches("false", scalar: scalar)
            || matches("null", scalar: scalar)
            || isValidJSONNumber(scalar)
    }

    private func matches(
        _ literal: StaticString,
        scalar: (start: UnsafePointer<UInt8>, count: Int)
    ) -> Bool {
        scalar.count == literal.utf8CodeUnitCount
            && memcmp(scalar.start, literal.utf8Start, scalar.count) == 0
    }

    private func isValidJSONNumber(
        _ scalar: (start: UnsafePointer<UInt8>, count: Int)
    ) -> Bool {
        var cursor = 0
        if cursor < scalar.count, scalar.start[cursor] == .minus {
            cursor += 1
        }
        guard cursor < scalar.count else {
            return false
        }

        if scalar.start[cursor] == .zero {
            cursor += 1
        } else {
            guard scalar.start[cursor] >= UInt8(ascii: "1"),
                scalar.start[cursor] <= .nine
            else {
                return false
            }
            repeat {
                cursor += 1
            } while cursor < scalar.count && scalar.start[cursor].isDigit
        }

        if cursor < scalar.count, scalar.start[cursor] == .dot {
            cursor += 1
            guard cursor < scalar.count, scalar.start[cursor].isDigit else {
                return false
            }
            repeat {
                cursor += 1
            } while cursor < scalar.count && scalar.start[cursor].isDigit
        }

        if cursor < scalar.count,
            scalar.start[cursor] == .lowerE || scalar.start[cursor] == .upperE
        {
            cursor += 1
            if cursor < scalar.count,
                scalar.start[cursor] == .plus || scalar.start[cursor] == .minus
            {
                cursor += 1
            }
            guard cursor < scalar.count, scalar.start[cursor].isDigit else {
                return false
            }
            repeat {
                cursor += 1
            } while cursor < scalar.count && scalar.start[cursor].isDigit
        }

        return cursor == scalar.count
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
