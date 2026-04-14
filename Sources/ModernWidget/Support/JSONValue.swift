import Foundation

enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let integer = try? container.decode(Int.self) {
            self = .number(Double(integer))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func flattenedPairs(limit: Int = .max, prefix: String? = nil) -> [QuotaPair] {
        var pairs: [QuotaPair] = []
        appendFlattenedPairs(into: &pairs, remaining: limit, prefix: prefix)
        return pairs
    }

    private func appendFlattenedPairs(into pairs: inout [QuotaPair], remaining: Int, prefix: String?) {
        guard remaining > 0 else { return }

        switch self {
        case let .string(value):
            pairs.append(QuotaPair(id: pairs.count, key: prefix ?? "value", value: value))
        case let .number(value):
            let rendered: String

            if value.rounded(.towardZero) == value,
               value >= Double(Int.min),
               value <= Double(Int.max) {
                rendered = String(Int(value))
            } else {
                rendered = String(value)
            }

            pairs.append(QuotaPair(id: pairs.count, key: prefix ?? "value", value: rendered))
        case let .bool(value):
            pairs.append(QuotaPair(id: pairs.count, key: prefix ?? "value", value: value ? "true" : "false"))
        case .null:
            pairs.append(QuotaPair(id: pairs.count, key: prefix ?? "value", value: "null"))
        case let .array(values):
            for (index, value) in values.enumerated() {
                guard pairs.count < remaining else { break }

                let key = if let prefix {
                    "\(prefix)[\(index)]"
                } else {
                    "[\(index)]"
                }

                value.appendFlattenedPairs(into: &pairs, remaining: remaining, prefix: key)
            }
        case let .object(values):
            for (key, value) in values.sorted(by: { $0.key < $1.key }) {
                guard pairs.count < remaining else { break }

                let nextKey = if let prefix {
                    "\(prefix).\(key)"
                } else {
                    key
                }

                value.appendFlattenedPairs(into: &pairs, remaining: remaining, prefix: nextKey)
            }
        }
    }
}
