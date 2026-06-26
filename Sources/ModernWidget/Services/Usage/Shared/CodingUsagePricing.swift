import Foundation

struct CodingUsageBillableTokens {
    let input: UInt64
    let output: UInt64
    let cacheCreation5m: UInt64
    let cacheCreation1h: UInt64
    let cacheRead: UInt64
    let usesFastPricing: Bool

    init(
        input: UInt64,
        output: UInt64,
        cacheCreation5m: UInt64 = 0,
        cacheCreation1h: UInt64 = 0,
        cacheRead: UInt64 = 0,
        usesFastPricing: Bool = false
    ) {
        self.input = input
        self.output = output
        self.cacheCreation5m = cacheCreation5m
        self.cacheCreation1h = cacheCreation1h
        self.cacheRead = cacheRead
        self.usesFastPricing = usesFastPricing
    }
}

enum CodingUsagePricing {
    private struct ModelPricing {
        let input: Double
        let output: Double
        let cacheCreate: Double
        let cacheRead: Double
        let fastMultiplier: Double

        init(
            input: Double,
            output: Double,
            cacheCreate: Double,
            cacheRead: Double,
            fastMultiplier: Double = 2.0
        ) {
            self.input = input
            self.output = output
            self.cacheCreate = cacheCreate
            self.cacheRead = cacheRead
            self.fastMultiplier = fastMultiplier
        }
    }

    static func cost(
        model: String?,
        tokens: CodingUsageBillableTokens
    ) -> Double {
        guard let model, let pricing = pricing(for: model) else {
            return 0
        }

        let multiplier = tokens.usesFastPricing ? pricing.fastMultiplier : 1
        return multiplier
            * (Double(tokens.input) * pricing.input
                + Double(tokens.output) * pricing.output
                + Double(tokens.cacheCreation5m) * pricing.cacheCreate
                + Double(tokens.cacheCreation1h) * pricing.input * 2
                + Double(tokens.cacheRead) * pricing.cacheRead)
    }

    private static func pricing(for model: String) -> ModelPricing? {
        let normalizedModel = normalized(model)
        if let exact = entries[normalizedModel] {
            return exact
        }

        return
            entries
            .filter { isVersionVariant(normalizedModel, of: $0.key) }
            .max { left, right in left.key.count < right.key.count }
            .map(\.value)
    }

    /// Matches a model to `key` when `key` is its prefix up to a `-`/`.` boundary, so
    /// `claude-sonnet-4-20250514` resolves to `claude-sonnet-4`. A version-numbered key
    /// (one ending in a digit) must not swallow a finer version: `claude-opus-4` stays
    /// distinct from `claude-opus-4-1`, while an 8-digit date suffix still matches.
    private static func isVersionVariant(_ model: String, of key: String) -> Bool {
        guard model.hasPrefix(key) else {
            return false
        }
        let suffix = model.dropFirst(key.count)
        guard let separator = suffix.first, separator == "-" || separator == "." else {
            return false
        }
        guard key.last?.isNumber == true else {
            return true
        }
        let versionDigits = suffix.dropFirst().prefix(while: \.isNumber)
        return versionDigits.isEmpty || versionDigits.count == 8
    }

    private static func normalized(_ model: String) -> String {
        model
            .lowercased()
            .replacingOccurrences(of: "anthropic/", with: "")
            .replacingOccurrences(of: "anthropic-", with: "")
            .replacingOccurrences(of: "openai/", with: "")
    }

    private static let entries: [String: ModelPricing] = [
        "claude-opus-4": ModelPricing(
            input: 15e-6,
            output: 75e-6,
            cacheCreate: 18.75e-6,
            cacheRead: 1.5e-6
        ),
        "claude-opus-4-5": ModelPricing(
            input: 5e-6,
            output: 25e-6,
            cacheCreate: 6.25e-6,
            cacheRead: 0.5e-6
        ),
        "claude-opus-4-6": ModelPricing(
            input: 5e-6,
            output: 25e-6,
            cacheCreate: 6.25e-6,
            cacheRead: 0.5e-6,
            fastMultiplier: 6
        ),
        "claude-opus-4-7": ModelPricing(
            input: 5e-6,
            output: 25e-6,
            cacheCreate: 6.25e-6,
            cacheRead: 0.5e-6,
            fastMultiplier: 6
        ),
        "claude-opus-4-8": ModelPricing(
            input: 5e-6,
            output: 25e-6,
            cacheCreate: 6.25e-6,
            cacheRead: 0.5e-6,
            fastMultiplier: 2
        ),
        "claude-fable-5": ModelPricing(
            input: 10e-6,
            output: 50e-6,
            cacheCreate: 12.5e-6,
            cacheRead: 1e-6
        ),
        "claude-haiku-4-5": ModelPricing(
            input: 1e-6,
            output: 5e-6,
            cacheCreate: 1.25e-6,
            cacheRead: 0.1e-6
        ),
        "claude-sonnet-4": ModelPricing(
            input: 3e-6,
            output: 15e-6,
            cacheCreate: 3.75e-6,
            cacheRead: 0.3e-6
        ),
        "claude-3-5-haiku": ModelPricing(
            input: 0.8e-6,
            output: 4e-6,
            cacheCreate: 1e-6,
            cacheRead: 0.08e-6
        ),
        "gpt-5": ModelPricing(
            input: 1.25e-6,
            output: 10e-6,
            cacheCreate: 1.25e-6,
            cacheRead: 0.125e-6
        ),
        "gpt-5.1": ModelPricing(
            input: 1.25e-6,
            output: 10e-6,
            cacheCreate: 1.25e-6,
            cacheRead: 0.125e-6
        ),
        "gpt-5.2": ModelPricing(
            input: 1.75e-6,
            output: 14e-6,
            cacheCreate: 1.75e-6,
            cacheRead: 0.175e-6
        ),
        "gpt-5.2-codex": ModelPricing(
            input: 1.75e-6,
            output: 14e-6,
            cacheCreate: 1.75e-6,
            cacheRead: 0.175e-6
        ),
        "gpt-5.3-codex": ModelPricing(
            input: 1.75e-6,
            output: 14e-6,
            cacheCreate: 1.75e-6,
            cacheRead: 0.175e-6
        ),
        "gpt-5.4": ModelPricing(
            input: 2.5e-6,
            output: 15e-6,
            cacheCreate: 2.5e-6,
            cacheRead: 0.25e-6
        ),
        "gpt-5.4-mini": ModelPricing(
            input: 0.75e-6,
            output: 4.5e-6,
            cacheCreate: 0.75e-6,
            cacheRead: 0.075e-6
        ),
        "gpt-5.4-nano": ModelPricing(
            input: 0.2e-6,
            output: 1.25e-6,
            cacheCreate: 0.2e-6,
            cacheRead: 0.02e-6
        ),
        "gpt-5.5": ModelPricing(
            input: 5e-6,
            output: 30e-6,
            cacheCreate: 5e-6,
            cacheRead: 0.5e-6,
            fastMultiplier: 2.5
        ),
    ]
}
