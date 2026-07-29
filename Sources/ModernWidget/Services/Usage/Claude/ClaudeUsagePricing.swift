struct ClaudeBillableUsage: Sendable {
    let inputTokens: UInt64
    let outputTokens: UInt64
    let cacheWrite5mTokens: UInt64
    let cacheWrite1hTokens: UInt64
    let cacheReadTokens: UInt64
    let usesUSDataResidency: Bool

    var totalTokens: UInt64 {
        inputTokens
            .saturatingAdd(outputTokens)
            .saturatingAdd(cacheWrite5mTokens)
            .saturatingAdd(cacheWrite1hTokens)
            .saturatingAdd(cacheReadTokens)
    }
}

/// Prices Claude log usage against the official Anthropic per-token rates.
enum ClaudeUsagePricing {
    static func totals(model: String?, usage: ClaudeBillableUsage) -> CodingUsageTotals? {
        guard let model, let entry = catalog.model(named: model) else {
            return nil
        }

        let rates = entry.rates
        let residencyMultiplier =
            usage.usesUSDataResidency && entry.supportsDataResidency ? 1.1 : 1
        let costPerMillion =
            Double(usage.inputTokens) * rates.input
            + Double(usage.outputTokens) * rates.output
            + Double(usage.cacheWrite5mTokens) * rates.cacheWrite5m
            + Double(usage.cacheWrite1hTokens) * rates.cacheWrite1h
            + Double(usage.cacheReadTokens) * rates.cacheRead

        return CodingUsageTotals(
            totalTokens: usage.totalTokens,
            costUSD: costPerMillion * residencyMultiplier / 1_000_000
        )
    }

    private struct Rates: Sendable {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite5m: Double
        let cacheWrite1h: Double
    }

    private struct Model: Sendable {
        let rates: Rates
        let supportsDataResidency: Bool
    }

    private static let fableRates = Rates(
        input: 10,
        output: 50,
        cacheRead: 1,
        cacheWrite5m: 12.5,
        cacheWrite1h: 20
    )
    private static let opusRates = Rates(
        input: 5,
        output: 25,
        cacheRead: 0.5,
        cacheWrite5m: 6.25,
        cacheWrite1h: 10
    )
    private static let sonnetRates = Rates(
        input: 3,
        output: 15,
        cacheRead: 0.3,
        cacheWrite5m: 3.75,
        cacheWrite1h: 6
    )
    private static let haikuRates = Rates(
        input: 1,
        output: 5,
        cacheRead: 0.1,
        cacheWrite5m: 1.25,
        cacheWrite1h: 2
    )

    private static let catalog = ModelCatalog<Model>(
        vendorPrefixes: ["anthropic/", "anthropic-"],
        models: [
            ("claude-fable-5", Model(rates: fableRates, supportsDataResidency: true)),
            ("claude-mythos-5", Model(rates: fableRates, supportsDataResidency: true)),
            ("claude-opus-5", Model(rates: opusRates, supportsDataResidency: true)),
            ("claude-opus-4-8", Model(rates: opusRates, supportsDataResidency: true)),
            ("claude-opus-4-7", Model(rates: opusRates, supportsDataResidency: true)),
            ("claude-opus-4-6", Model(rates: opusRates, supportsDataResidency: true)),
            ("claude-sonnet-5", Model(rates: sonnetRates, supportsDataResidency: true)),
            ("claude-haiku-4-5", Model(rates: haikuRates, supportsDataResidency: false)),
        ]
    )
}
