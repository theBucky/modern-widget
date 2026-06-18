import Foundation

enum CodingUsageAgent: CaseIterable, Hashable, Sendable {
    case claude
    case codex

    var title: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }
}

struct CodingTokenCounts: Equatable, Sendable {
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
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationTokens += other.cacheCreationTokens
        cacheReadTokens += other.cacheReadTokens
        reasoningTokens += other.reasoningTokens
        totalTokens += other.totalTokens
        costUSD += other.costUSD
    }

    static func claude(
        inputTokens: UInt64,
        outputTokens: UInt64,
        cacheCreationTokens: UInt64,
        cacheReadTokens: UInt64,
        costUSD: Double
    ) -> Self {
        Self(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens,
            totalTokens: inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens,
            costUSD: costUSD
        )
    }

    static func codex(
        inputTokens: UInt64,
        cachedInputTokens: UInt64,
        outputTokens: UInt64,
        reasoningTokens: UInt64,
        costUSD: Double
    ) -> Self {
        Self(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cachedInputTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: inputTokens + outputTokens,
            costUSD: costUSD
        )
    }
}

struct CodingUsageDaySummary: Equatable, Sendable {
    let date: Date
    let counts: CodingTokenCounts
}

struct CodingUsageAgentSummary: Equatable, Sendable {
    let agent: CodingUsageAgent
    let dailyCounts: [CodingUsageDaySummary]

    var totalCounts: CodingTokenCounts {
        dailyCounts.reduce(into: CodingTokenCounts()) { total, day in
            total.add(day.counts)
        }
    }
}

struct CodingUsageReport: Equatable, Sendable {
    /// `nil` until the first load completes.
    let generatedAt: Date?
    let agents: [CodingUsageAgentSummary]

    var hasUsage: Bool {
        agents.contains { summary in
            summary.dailyCounts.contains { $0.counts.hasUsage }
        }
    }

    static var empty: Self {
        Self(
            generatedAt: nil,
            agents: CodingUsageAgent.allCases.map { agent in
                CodingUsageAgentSummary(agent: agent, dailyCounts: [])
            }
        )
    }
}

struct CodingUsageDateScope: Equatable, Sendable {
    let now: Date
    let history: DateInterval
    let historyDays: [Date]

    private let calendar: Calendar

    init(now: Date = .now, calendar: Calendar = .current) {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let rollingStart = calendar.date(byAdding: .day, value: -29, to: todayStart)!
        let monthStart = calendar.dateInterval(of: .month, for: now)!.start
        let historyStart = min(rollingStart, monthStart)
        let dayCount = calendar.dateComponents([.day], from: historyStart, to: tomorrowStart).day!

        self.now = now
        self.calendar = calendar
        self.history = DateInterval(start: historyStart, end: tomorrowStart)
        self.historyDays = (0..<dayCount).map {
            calendar.date(byAdding: .day, value: $0, to: historyStart)!
        }
    }

    func historyDay(containing date: Date) -> Date? {
        guard date >= history.start && date < history.end else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }
}
