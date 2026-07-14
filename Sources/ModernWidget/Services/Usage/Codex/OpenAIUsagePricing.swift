enum OpenAIUsagePricing {
    struct Resolver {
        private var models: [String: Model] = [:]

        mutating func totals(
            model rawModel: String,
            usage: CodexRawUsage
        ) -> CodingUsageTotals? {
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
        let longContext: LongContext?

        func matches(_ candidate: String) -> Bool {
            candidate == name
                || candidate.hasPrefix(name + "-")
                    && isSnapshotDate(candidate.dropFirst(name.count + 1))
        }

        func rates(inputTokens: UInt64) -> Rates {
            guard let longContext, inputTokens > longContext.threshold else {
                return standardRates
            }
            return longContext.rates
        }
    }

    private static let catalog: [Model] = [
        model(name: "gpt-5.3-codex", input: 1.75, output: 14, cacheRead: 0.175, cacheWrite: 0),
        model(
            name: "gpt-5.4",
            input: 2.5,
            output: 15,
            cacheRead: 0.25,
            cacheWrite: 0,
            longContext: LongContext(
                threshold: 272_000,
                rates: Rates(input: 5, output: 22.5, cacheRead: 0.5, cacheWrite: 0)
            )
        ),
        model(name: "gpt-5.4-mini", input: 0.75, output: 4.5, cacheRead: 0.075, cacheWrite: 0),
        model(name: "gpt-5.4-nano", input: 0.2, output: 1.25, cacheRead: 0.02, cacheWrite: 0),
        model(
            name: "gpt-5.5",
            input: 5,
            output: 30,
            cacheRead: 0.5,
            cacheWrite: 0,
            longContext: LongContext(
                threshold: 272_000,
                rates: Rates(input: 10, output: 45, cacheRead: 1, cacheWrite: 0)
            )
        ),
        model(
            name: "gpt-5.6-sol",
            input: 5,
            output: 30,
            cacheRead: 0.5,
            cacheWrite: 6.25,
            longContext: LongContext(
                threshold: 272_000,
                rates: Rates(input: 10, output: 45, cacheRead: 1, cacheWrite: 12.5)
            )
        ),
        model(
            name: "gpt-5.6-terra",
            input: 2.5,
            output: 15,
            cacheRead: 0.25,
            cacheWrite: 3.125,
            longContext: LongContext(
                threshold: 272_000,
                rates: Rates(input: 5, output: 22.5, cacheRead: 0.5, cacheWrite: 6.25)
            )
        ),
        model(
            name: "gpt-5.6-luna",
            input: 1,
            output: 6,
            cacheRead: 0.1,
            cacheWrite: 1.25,
            longContext: LongContext(
                threshold: 272_000,
                rates: Rates(input: 2, output: 9, cacheRead: 0.2, cacheWrite: 2.5)
            )
        ),
    ]

    private static func model(
        name: String,
        input: Double,
        output: Double,
        cacheRead: Double,
        cacheWrite: Double,
        longContext: LongContext? = nil
    ) -> Model {
        Model(
            name: name,
            standardRates: Rates(
                input: input,
                output: output,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite
            ),
            longContext: longContext
        )
    }

    private static func normalize(_ model: String) -> String {
        let normalized = model.lowercased()
        return normalized.hasPrefix("openai/") ? String(normalized.dropFirst(7)) : normalized
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
