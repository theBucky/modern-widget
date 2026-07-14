import Foundation

struct CodingUsageTotals: Equatable, Sendable {
    var totalTokens: UInt64 = 0
    var costUSD: Double = 0

    var hasUsage: Bool {
        totalTokens > 0 || costUSD > 0
    }

    var hasCost: Bool {
        costUSD > 0
    }

    mutating func add(_ other: Self) {
        totalTokens = totalTokens.saturatingAdd(other.totalTokens)
        costUSD += other.costUSD
    }
}

struct CodingUsageEvent: Sendable {
    let timestamp: Date
    let totals: CodingUsageTotals
}
