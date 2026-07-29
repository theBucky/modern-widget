/// Fixed model rate catalog shared by the pricing tables. A raw model name matches
/// an entry after lowercasing and vendor-prefix stripping, either exactly or as
/// `<name>-<snapshot-date>`, where a snapshot date is `YYYYMMDD` or `YYYY-MM-DD`.
struct ModelCatalog<Model: Sendable>: Sendable {
    private let vendorPrefixes: [String]
    private let models: [(name: String, model: Model)]

    init(vendorPrefixes: [String], models: [(name: String, model: Model)]) {
        self.vendorPrefixes = vendorPrefixes
        self.models = models
    }

    func model(named rawName: String) -> Model? {
        var name = Substring(rawName.lowercased())
        if let prefix = vendorPrefixes.first(where: { name.hasPrefix($0) }) {
            name = name.dropFirst(prefix.count)
        }
        return models.first { matches(name, entry: $0.name) }?.model
    }

    private func matches(_ candidate: Substring, entry name: String) -> Bool {
        guard candidate.hasPrefix(name) else {
            return false
        }
        let suffix = candidate.dropFirst(name.count)
        if suffix.isEmpty {
            return true
        }
        return suffix.first == "-" && Self.isSnapshotDate(suffix.dropFirst())
    }

    private static func isSnapshotDate(_ suffix: Substring) -> Bool {
        if suffix.count == 8 {
            return suffix.allSatisfy(\.isNumber)
        }
        guard suffix.count == 10 else {
            return false
        }
        return suffix.enumerated().allSatisfy { index, character in
            index == 4 || index == 7 ? character == "-" : character.isNumber
        }
    }
}
