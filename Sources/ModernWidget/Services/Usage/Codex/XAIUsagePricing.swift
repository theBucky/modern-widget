enum XAIUsagePricing {
    static func totals(
        model rawModel: String,
        usage: CodexRawUsage
    ) -> CodingUsageTotals? {
        guard normalize(rawModel) == model.name else {
            return nil
        }

        let rates = model.rates(inputTokens: usage.inputTokens)
        let ordinaryInput = usage.inputTokens - usage.cachedInputTokens
        let costPerMillion =
            Double(ordinaryInput) * rates.input
            + Double(usage.cachedInputTokens) * rates.cacheRead
            + Double(usage.outputTokens) * rates.output

        return CodingUsageTotals(
            totalTokens: usage.inputTokens.saturatingAdd(usage.outputTokens),
            costUSD: costPerMillion / 1_000_000
        )
    }

    private struct Rates {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
    }

    private struct LongContext {
        let threshold: UInt64
        let rates: Rates
    }

    private struct Model {
        let name: String
        let standardRates: Rates
        let longContext: LongContext

        func rates(inputTokens: UInt64) -> Rates {
            inputTokens > longContext.threshold ? longContext.rates : standardRates
        }
    }

    private static let model = Model(
        name: "grok-4.5",
        standardRates: Rates(input: 2, output: 6, cacheRead: 0.5, cacheWrite: 0),
        longContext: LongContext(
            threshold: 200_000,
            rates: Rates(input: 4, output: 12, cacheRead: 1, cacheWrite: 0)
        )
    )

    private static func normalize(_ model: String) -> String {
        let normalized = model.lowercased()
        return normalized.hasPrefix("xai/") ? String(normalized.dropFirst(4)) : normalized
    }
}
