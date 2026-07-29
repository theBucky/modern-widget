import Foundation

enum CodingUsagePeriod: CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case last7Days
    case last30Days

    var id: Self { self }
}

struct CodingUsagePresentation: Equatable, Sendable {
    struct PeriodTotal: Equatable, Identifiable, Sendable {
        let period: CodingUsagePeriod
        let totals: CodingUsageTotals

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
        let todayInterval = scope.interval(for: .today)
        let todayTotals = Self.totals(in: todayInterval, sections: sections)
        let yesterdayTotals = Self.totals(
            in: scope.interval(for: .yesterday),
            sections: sections
        )

        self.isLoading = report.isLoading
        self.today = CodingUsageTodaySummary(
            date: todayInterval.start,
            totals: todayTotals,
            costTrend: CodingUsageCostTrend(
                currentCostUSD: todayTotals.costUSD,
                previousCostUSD: yesterdayTotals.costUSD
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
                        totals: totals(in: scope.interval(for: period), days: summary.days)
                    )
                },
                chartDays: summary.days
            )
        }
    }

    private static func totals(
        in interval: DateInterval,
        sections: [AgentSection]
    ) -> CodingUsageTotals {
        sections.reduce(into: CodingUsageTotals()) { total, section in
            total.add(totals(in: interval, days: section.chartDays))
        }
    }

    private static func totals(
        in interval: DateInterval,
        days: [CodingUsageDaySummary]
    ) -> CodingUsageTotals {
        days.reduce(into: CodingUsageTotals()) { total, day in
            guard day.date >= interval.start && day.date < interval.end else {
                return
            }
            total.add(day.totals)
        }
    }
}
