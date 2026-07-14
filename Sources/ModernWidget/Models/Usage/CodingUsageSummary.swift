import Foundation

enum CodingUsageAgent: String, CaseIterable, Hashable, Sendable {
    case claude
    case codex
    case pi

    static func ordered(_ agents: Set<Self>) -> [Self] {
        allCases.filter { agents.contains($0) }
    }

    var title: LocalizedStringResource {
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
    let totals: CodingUsageTotals
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
    let totals: CodingUsageTotals
    let costTrend: CodingUsageCostTrend
}

struct CodingUsageAgentSummary: Equatable, Sendable {
    let agent: CodingUsageAgent
    let days: [CodingUsageDaySummary]

    /// A full zero-usage grid over `days`, matching the shape the loader produces so
    /// placeholders and freshly enabled agents share the real data's day axis.
    static func zeroed(agent: CodingUsageAgent, days: [Date]) -> Self {
        Self(
            agent: agent,
            days: days.map { CodingUsageDaySummary(date: $0, totals: CodingUsageTotals()) }
        )
    }
}

struct CodingUsageReport: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case loading
        case loaded(generatedAt: Date)
    }

    let state: State
    let agents: [CodingUsageAgentSummary]

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
