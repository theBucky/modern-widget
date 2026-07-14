struct CodexUsageCostResolver {
    private var openAI = OpenAIUsagePricing.Resolver()

    mutating func totals(
        model: String?,
        usage: CodexRawUsage
    ) -> CodingUsageTotals? {
        guard let model else {
            return nil
        }

        // GPT 5.6 cache writes are billable, but Codex rollouts persist neither their
        // token count nor the request tier, so price only observable tokens at standard rates.
        return openAI.totals(model: model, usage: usage)
            ?? XAIUsagePricing.totals(model: model, usage: usage)
    }
}
