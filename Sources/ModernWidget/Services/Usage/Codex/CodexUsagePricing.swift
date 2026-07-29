/// Prices Codex rollout usage against the official OpenAI per-token rates.
enum CodexUsagePricing {
    static func totals(model: String?, usage: CodexRawUsage) -> CodingUsageTotals? {
        guard let model, let entry = catalog.model(named: model) else {
            return nil
        }

        let rates = entry.rates(inputTokens: usage.inputTokens)
        let ordinaryInput =
            usage.inputTokens - usage.cachedInputTokens - usage.cacheWriteInputTokens
        let costPerMillion =
            Double(ordinaryInput) * rates.input
            + Double(usage.cachedInputTokens) * rates.cacheRead
            + Double(usage.cacheWriteInputTokens) * rates.cacheWrite
            + Double(usage.outputTokens) * rates.output

        return CodingUsageTotals(
            totalTokens: usage.inputTokens.saturatingAdd(usage.outputTokens),
            costUSD: costPerMillion / 1_000_000
        )
    }

    private struct Rates: Sendable {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
    }

    private struct LongContext: Sendable {
        let threshold: UInt64
        let rates: Rates
    }

    private struct Model: Sendable {
        let standardRates: Rates
        let longContext: LongContext?

        func rates(inputTokens: UInt64) -> Rates {
            guard let longContext, inputTokens > longContext.threshold else {
                return standardRates
            }
            return longContext.rates
        }
    }

    private static let catalog = ModelCatalog<Model>(
        vendorPrefixes: ["openai/"],
        models: [
            (
                "gpt-5.3-codex",
                model(input: 1.75, output: 14, cacheRead: 0.175, cacheWrite: 0)
            ),
            (
                "gpt-5.4",
                model(
                    input: 2.5,
                    output: 15,
                    cacheRead: 0.25,
                    cacheWrite: 0,
                    longContext: LongContext(
                        threshold: 272_000,
                        rates: Rates(input: 5, output: 22.5, cacheRead: 0.5, cacheWrite: 0)
                    )
                )
            ),
            (
                "gpt-5.4-mini",
                model(input: 0.75, output: 4.5, cacheRead: 0.075, cacheWrite: 0)
            ),
            (
                "gpt-5.4-nano",
                model(input: 0.2, output: 1.25, cacheRead: 0.02, cacheWrite: 0)
            ),
            (
                "gpt-5.5",
                model(
                    input: 5,
                    output: 30,
                    cacheRead: 0.5,
                    cacheWrite: 0,
                    longContext: LongContext(
                        threshold: 272_000,
                        rates: Rates(input: 10, output: 45, cacheRead: 1, cacheWrite: 0)
                    )
                )
            ),
            (
                "gpt-5.6-sol",
                model(
                    input: 5,
                    output: 30,
                    cacheRead: 0.5,
                    cacheWrite: 6.25,
                    longContext: LongContext(
                        threshold: 272_000,
                        rates: Rates(input: 10, output: 45, cacheRead: 1, cacheWrite: 12.5)
                    )
                )
            ),
            (
                "gpt-5.6-terra",
                model(
                    input: 2.5,
                    output: 15,
                    cacheRead: 0.25,
                    cacheWrite: 3.125,
                    longContext: LongContext(
                        threshold: 272_000,
                        rates: Rates(input: 5, output: 22.5, cacheRead: 0.5, cacheWrite: 6.25)
                    )
                )
            ),
            (
                "gpt-5.6-luna",
                model(
                    input: 1,
                    output: 6,
                    cacheRead: 0.1,
                    cacheWrite: 1.25,
                    longContext: LongContext(
                        threshold: 272_000,
                        rates: Rates(input: 2, output: 9, cacheRead: 0.2, cacheWrite: 2.5)
                    )
                )
            ),
        ]
    )

    private static func model(
        input: Double,
        output: Double,
        cacheRead: Double,
        cacheWrite: Double,
        longContext: LongContext? = nil
    ) -> Model {
        Model(
            standardRates: Rates(
                input: input,
                output: output,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite
            ),
            longContext: longContext
        )
    }
}
