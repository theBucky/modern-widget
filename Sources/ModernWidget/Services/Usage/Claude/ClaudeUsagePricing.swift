struct ClaudeBillableUsage: Sendable {
    let inputTokens: UInt64
    let outputTokens: UInt64
    let cacheWrite5mTokens: UInt64
    let cacheWrite1hTokens: UInt64
    let cacheReadTokens: UInt64
    let usesUSDataResidency: Bool

    var totalTokens: UInt64 {
        contextInputTokens.saturatingAdd(outputTokens)
    }

    var contextInputTokens: UInt64 {
        inputTokens
            .saturatingAdd(cacheWrite5mTokens)
            .saturatingAdd(cacheWrite1hTokens)
            .saturatingAdd(cacheReadTokens)
    }
}

enum ClaudeUsagePricing {
    struct Resolver {
        private var models: [String: Model] = [:]

        mutating func totals(
            model rawModel: String?,
            usage: ClaudeBillableUsage
        ) -> CodingUsageTotals? {
            guard let rawModel else {
                return nil
            }

            let name = normalize(rawModel)
            let model: Model
            if let cached = models[name] {
                model = cached
            } else {
                guard let resolved = catalog.first(where: { $0.matches(name) }) else {
                    return nil
                }
                models[name] = resolved
                model = resolved
            }

            let rates = model.rates(contextInputTokens: usage.contextInputTokens)
            let residencyMultiplier =
                usage.usesUSDataResidency && model.supportsDataResidency ? 1.1 : 1
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
    }

    private struct Rates {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite5m: Double
        let cacheWrite1h: Double
    }

    private struct LongContext {
        let threshold: UInt64
        let rates: Rates
    }

    private struct Model {
        let name: String
        let standardRates: Rates
        let longContext: LongContext?
        let supportsDataResidency: Bool

        func matches(_ candidate: String) -> Bool {
            candidate == name
                || candidate.hasPrefix(name + "-")
                    && isSnapshotDate(candidate.dropFirst(name.count + 1))
        }

        func rates(contextInputTokens: UInt64) -> Rates {
            guard let longContext, contextInputTokens > longContext.threshold else {
                return standardRates
            }
            return longContext.rates
        }
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
    private static let sonnetLongContext = LongContext(
        threshold: 200_000,
        rates: Rates(
            input: 6,
            output: 22.5,
            cacheRead: 0.6,
            cacheWrite5m: 7.5,
            cacheWrite1h: 12
        )
    )

    private static let catalog: [Model] = [
        Model(
            name: "claude-fable-5",
            standardRates: fableRates,
            longContext: nil,
            supportsDataResidency: true
        ),
        Model(
            name: "claude-mythos-5",
            standardRates: fableRates,
            longContext: nil,
            supportsDataResidency: true
        ),
        Model(
            name: "claude-opus-4-8",
            standardRates: opusRates,
            longContext: nil,
            supportsDataResidency: true
        ),
        Model(
            name: "claude-opus-4-7",
            standardRates: opusRates,
            longContext: nil,
            supportsDataResidency: true
        ),
        Model(
            name: "claude-opus-4-6",
            standardRates: opusRates,
            longContext: nil,
            supportsDataResidency: true
        ),
        Model(
            name: "claude-opus-4-5",
            standardRates: opusRates,
            longContext: nil,
            supportsDataResidency: false
        ),
        Model(
            name: "claude-sonnet-5",
            standardRates: sonnetRates,
            longContext: nil,
            supportsDataResidency: true
        ),
        Model(
            name: "claude-sonnet-4-6",
            standardRates: sonnetRates,
            longContext: nil,
            supportsDataResidency: true
        ),
        Model(
            name: "claude-sonnet-4-5",
            standardRates: sonnetRates,
            longContext: sonnetLongContext,
            supportsDataResidency: false
        ),
        Model(
            name: "claude-haiku-4-5",
            standardRates: Rates(
                input: 1,
                output: 5,
                cacheRead: 0.1,
                cacheWrite5m: 1.25,
                cacheWrite1h: 2
            ),
            longContext: nil,
            supportsDataResidency: false
        ),
    ]

    private static func normalize(_ model: String) -> String {
        let normalized = model.lowercased()
        if normalized.hasPrefix("anthropic/") {
            return String(normalized.dropFirst(10))
        }
        if normalized.hasPrefix("anthropic-") {
            return String(normalized.dropFirst(10))
        }
        return normalized
    }

    private static func isSnapshotDate(_ suffix: Substring) -> Bool {
        suffix.count == 8 && suffix.allSatisfy(\.isNumber)
    }
}
