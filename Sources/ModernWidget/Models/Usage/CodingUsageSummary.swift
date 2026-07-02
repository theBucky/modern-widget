import Foundation

enum CodingUsageAgent: String, CaseIterable, Hashable, Sendable {
    case claude
    case codex
    case pi

    static func ordered(_ agents: Set<Self>) -> [Self] {
        allCases.filter { agents.contains($0) }
    }

    var title: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .pi:
            return "Pi"
        }
    }
}

struct CodingUsageDaySummary: Equatable, Sendable {
    let date: Date
    let counts: CodingTokenCounts
}

struct CodingUsagePeriodRow: Equatable, Identifiable, Sendable {
    let title: String
    let counts: CodingTokenCounts

    var id: String { title }
}

struct CodingUsageCostTrend: Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        case up
        case down
        case flat
    }

    let percent: Double

    var direction: Direction {
        if percent > 0 {
            return .up
        }
        if percent < 0 {
            return .down
        }
        return .flat
    }

    init(currentCostUSD: Double, previousCostUSD: Double) {
        let rawPercent: Double
        if previousCostUSD > 0 {
            rawPercent = (currentCostUSD - previousCostUSD) / previousCostUSD * 100
        } else {
            rawPercent = currentCostUSD > 0 ? 100 : 0
        }

        let rounded = (rawPercent * 10).rounded(.toNearestOrEven) / 10
        self.percent = rounded == 0 ? 0 : rounded
    }
}

struct CodingUsageTodaySummary: Equatable, Sendable {
    let date: Date
    let counts: CodingTokenCounts
    let costTrend: CodingUsageCostTrend
}

struct CodingUsageAgentSummary: Equatable, Sendable {
    let agent: CodingUsageAgent
    let dailyCounts: [CodingUsageDaySummary]

    /// A full zero-usage grid over `days`, matching the shape the loader produces so
    /// placeholders and freshly enabled agents share the real data's day axis.
    static func zeroed(agent: CodingUsageAgent, days: [Date]) -> Self {
        Self(
            agent: agent,
            dailyCounts: days.map { CodingUsageDaySummary(date: $0, counts: CodingTokenCounts()) }
        )
    }

    var totalCounts: CodingTokenCounts {
        dailyCounts.reduce(into: CodingTokenCounts()) { total, day in
            total.add(day.counts)
        }
    }

    func usageRows(in scope: CodingUsageDateScope) -> [CodingUsagePeriodRow] {
        [
            ("Today", scope.today),
            ("Yesterday", scope.yesterday),
            ("Last 7 Days", scope.last7Days),
            ("Last 30 Days", scope.last30Days),
        ].map { title, interval in
            CodingUsagePeriodRow(title: title, counts: counts(in: interval))
        }
    }

    func counts(in interval: DateInterval) -> CodingTokenCounts {
        dailyCounts.reduce(into: CodingTokenCounts()) { total, day in
            guard day.date >= interval.start && day.date < interval.end else {
                return
            }
            total.add(day.counts)
        }
    }
}

struct CodingUsageReport: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case loading
        case loaded(generatedAt: Date)
    }

    let state: State
    let agents: [CodingUsageAgentSummary]

    var hasUsage: Bool {
        agents.contains { summary in
            summary.dailyCounts.contains { $0.counts.hasUsage }
        }
    }

    func counts(in interval: DateInterval) -> CodingTokenCounts {
        agents.reduce(into: CodingTokenCounts()) { total, summary in
            total.add(summary.counts(in: interval))
        }
    }

    func todaySummary(in scope: CodingUsageDateScope) -> CodingUsageTodaySummary {
        let today = counts(in: scope.today)
        let yesterday = counts(in: scope.yesterday)

        return CodingUsageTodaySummary(
            date: scope.today.start,
            counts: today,
            costTrend: CodingUsageCostTrend(
                currentCostUSD: today.costUSD,
                previousCostUSD: yesterday.costUSD
            )
        )
    }

    func showingAgents(_ enabledAgents: Set<CodingUsageAgent>) -> Self {
        let summariesByAgent = Dictionary(uniqueKeysWithValues: agents.map { ($0.agent, $0) })
        let dayAxis = agents.first?.dailyCounts.map(\.date) ?? []

        return Self(
            state: state,
            agents: CodingUsageAgent.ordered(enabledAgents).map { agent in
                summariesByAgent[agent] ?? .zeroed(agent: agent, days: dayAxis)
            }
        )
    }

    /// Loading placeholder with the same full-grid shape as a loaded report, so the
    /// chart skeleton renders every day and no leaf method has to repair an empty axis.
    static func placeholder(
        scope: CodingUsageDateScope,
        agents: [CodingUsageAgent] = CodingUsageAgent.allCases
    ) -> Self {
        Self(
            state: .loading,
            agents: agents.map { .zeroed(agent: $0, days: scope.historyDays) }
        )
    }
}
