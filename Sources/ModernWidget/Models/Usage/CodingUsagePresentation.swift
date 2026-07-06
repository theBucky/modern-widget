import Foundation

enum CodingUsagePeriod: CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case last7Days
    case last30Days

    var id: Self { self }

    func interval(in scope: CodingUsageDateScope) -> DateInterval {
        switch self {
        case .today:
            return scope.today
        case .yesterday:
            return scope.yesterday
        case .last7Days:
            return scope.last7Days
        case .last30Days:
            return scope.last30Days
        }
    }
}

struct CodingUsagePresentation: Equatable, Sendable {
    struct PeriodTotal: Equatable, Identifiable, Sendable {
        let period: CodingUsagePeriod
        let counts: CodingTokenCounts

        var id: CodingUsagePeriod { period }
    }

    struct AgentSection: Equatable, Identifiable, Sendable {
        let agent: CodingUsageAgent
        let periodTotals: [PeriodTotal]
        let chartDays: [CodingUsageDaySummary]

        var id: CodingUsageAgent { agent }
    }

    let isLoading: Bool
    let today: CodingUsageTodaySummary
    let sections: [AgentSection]

    init(
        report: CodingUsageReport,
        scope: CodingUsageDateScope,
        activeAgents: Set<CodingUsageAgent>
    ) {
        let sections = Self.sections(
            report: report,
            scope: scope,
            activeAgents: activeAgents
        )
        let todayCounts = Self.counts(
            in: CodingUsagePeriod.today.interval(in: scope),
            sections: sections
        )
        let yesterdayCounts = Self.counts(
            in: CodingUsagePeriod.yesterday.interval(in: scope),
            sections: sections
        )

        self.isLoading = report.state == .loading
        self.today = CodingUsageTodaySummary(
            date: scope.today.start,
            counts: todayCounts,
            costTrend: CodingUsageCostTrend(
                currentCostUSD: todayCounts.costUSD,
                previousCostUSD: yesterdayCounts.costUSD
            )
        )
        self.sections = sections
    }

    private static func sections(
        report: CodingUsageReport,
        scope: CodingUsageDateScope,
        activeAgents: Set<CodingUsageAgent>
    ) -> [AgentSection] {
        let summariesByAgent = Dictionary(
            uniqueKeysWithValues: report.agents.map { ($0.agent, $0) })
        let dayAxis = scope.historyDays

        return CodingUsageAgent.ordered(activeAgents).map { agent in
            let summary = summariesByAgent[agent] ?? .zeroed(agent: agent, days: dayAxis)
            return AgentSection(
                agent: agent,
                periodTotals: CodingUsagePeriod.allCases.map { period in
                    PeriodTotal(
                        period: period,
                        counts: counts(in: period.interval(in: scope), days: summary.dailyCounts)
                    )
                },
                chartDays: summary.dailyCounts
            )
        }
    }

    private static func counts(
        in interval: DateInterval,
        sections: [AgentSection]
    ) -> CodingTokenCounts {
        sections.reduce(into: CodingTokenCounts()) { total, section in
            total.add(counts(in: interval, days: section.chartDays))
        }
    }

    private static func counts(
        in interval: DateInterval,
        days: [CodingUsageDaySummary]
    ) -> CodingTokenCounts {
        days.reduce(into: CodingTokenCounts()) { total, day in
            guard day.date >= interval.start && day.date < interval.end else {
                return
            }
            total.add(day.counts)
        }
    }
}
