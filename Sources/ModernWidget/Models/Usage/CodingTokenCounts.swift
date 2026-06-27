struct CodingTokenCounts: Hashable, Sendable {
    var inputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var cacheCreationTokens: UInt64 = 0
    var cacheReadTokens: UInt64 = 0
    var reasoningTokens: UInt64 = 0
    var totalTokens: UInt64 = 0
    var costUSD: Double = 0

    var hasUsage: Bool {
        inputTokens > 0 || outputTokens > 0 || cacheCreationTokens > 0 || cacheReadTokens > 0
            || reasoningTokens > 0 || totalTokens > 0 || costUSD > 0
    }

    mutating func add(_ other: CodingTokenCounts) {
        inputTokens = inputTokens.saturatingAdd(other.inputTokens)
        outputTokens = outputTokens.saturatingAdd(other.outputTokens)
        cacheCreationTokens = cacheCreationTokens.saturatingAdd(other.cacheCreationTokens)
        cacheReadTokens = cacheReadTokens.saturatingAdd(other.cacheReadTokens)
        reasoningTokens = reasoningTokens.saturatingAdd(other.reasoningTokens)
        totalTokens = totalTokens.saturatingAdd(other.totalTokens)
        costUSD += other.costUSD
    }
}
