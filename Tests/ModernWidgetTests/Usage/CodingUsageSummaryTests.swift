import Foundation
import Testing

@testable import ModernWidget

@Suite("Coding usage summary")
struct CodingUsageSummaryTests {
    @Test("summarizes usage windows")
    func summarizesUsageWindows() {
        let calendar = gregorianUTC()
        let now = date(2026, 6, 18, 12)
        let summary = CodingUsageAgentSummary(
            agent: .claude,
            dailyCounts: [
                day(2026, 6, 1, 1),
                day(2026, 6, 17, 2),
                day(2026, 6, 18, 3),
            ]
        )

        let rows = summary.usageRows(in: CodingUsageDateScope(now: now, calendar: calendar))

        #expect(rows.map(\.title) == ["Today", "Yesterday", "Last 7 Days", "Last 30 Days"])
        #expect(rows.map(\.counts.costUSD) == [3, 2, 5, 6])
        #expect(
            rows.map(\.counts.totalTokens) == [
                3_000_000_000,
                2_000_000_000,
                5_000_000_000,
                6_000_000_000,
            ])
    }

    @Test("summarizes today's report total across agents")
    func summarizesTodayReportTotalAcrossAgents() {
        let calendar = gregorianUTC()
        let now = date(2026, 6, 18, 12)
        let report = CodingUsageReport(
            state: .loaded(generatedAt: now),
            agents: [
                CodingUsageAgentSummary(
                    agent: .claude,
                    dailyCounts: [day(2026, 6, 18, 1), day(2026, 6, 17, 9)]
                ),
                CodingUsageAgentSummary(
                    agent: .codex,
                    dailyCounts: [day(2026, 6, 18, 2)]
                ),
                CodingUsageAgentSummary(
                    agent: .pi,
                    dailyCounts: [day(2026, 6, 18, 3)]
                ),
            ]
        )

        let counts = report.todaySummary(in: CodingUsageDateScope(now: now, calendar: calendar))
            .counts

        #expect(counts.costUSD == 6)
        #expect(counts.totalTokens == 6_000_000_000)
    }

    @Test("summarizes today's cost trend across agents")
    func summarizesTodayCostTrendAcrossAgents() {
        let calendar = gregorianUTC()
        let now = date(2026, 6, 18, 12)
        let report = CodingUsageReport(
            state: .loaded(generatedAt: now),
            agents: [
                CodingUsageAgentSummary(
                    agent: .claude,
                    dailyCounts: [day(2026, 6, 17, 1), day(2026, 6, 18, 2)]
                ),
                CodingUsageAgentSummary(
                    agent: .codex,
                    dailyCounts: [day(2026, 6, 17, 3), day(2026, 6, 18, 4)]
                ),
                CodingUsageAgentSummary(agent: .pi, dailyCounts: []),
            ]
        )

        let trend = report.todaySummary(in: CodingUsageDateScope(now: now, calendar: calendar))
            .costTrend

        #expect(trend.percent == 50)
        #expect(trend.direction == .up)
    }

    @Test("shows only enabled agents in stable order, filling a missing one with a zero grid")
    func showsOnlyEnabledAgentsInStableOrder() {
        let now = date(2026, 6, 18, 12)
        let report = CodingUsageReport(
            state: .loaded(generatedAt: now),
            agents: [
                CodingUsageAgentSummary(agent: .claude, dailyCounts: [day(2026, 6, 18, 1)]),
                CodingUsageAgentSummary(agent: .codex, dailyCounts: [day(2026, 6, 18, 2)]),
            ]
        ).showingAgents([.pi, .claude])

        #expect(report.state == .loaded(generatedAt: now))
        #expect(report.agents.map(\.agent) == [.claude, .pi])
        #expect(report.agents[0].totalCounts.costUSD == 1)
        #expect(report.agents[1].dailyCounts.map(\.date) == [date(2026, 6, 18)])
        #expect(!report.agents[1].totalCounts.hasUsage)
    }

    @Test("formats small costs with four decimals")
    func formatsSmallCostsWithFourDecimals() {
        #expect(formatCodingUsageCost(0.0042) == "$0.0042")
    }

    @Test("formats token counts with compact units")
    func formatsTokenCountsWithCompactUnits() {
        #expect(formatCodingUsageTokens(999) == "999.0 tokens")
        #expect(formatCodingUsageTokens(1_200) == "1.2K tokens")
        #expect(formatCodingUsageTokens(999_950) == "1.0M tokens")
        #expect(formatCodingUsageTokens(12_300_000_000) == "12.3B tokens")
        #expect(formatCodingUsageTokens(1_200_000_000_000) == "1.2T tokens")
    }

    @Test("token unit promotes to the next unit when rounding crosses a thousand")
    func tokenUnitPromotionBoundaries() {
        #expect(formatCodingUsageTokens(999_949) == "999.9K tokens")
        #expect(formatCodingUsageTokens(999_950) == "1.0M tokens")
        #expect(formatCodingUsageTokens(999_949_999) == "999.9M tokens")
        #expect(formatCodingUsageTokens(999_950_000) == "1.0B tokens")
    }

    @Test("formats cost trend percent")
    func formatsCostTrendPercent() {
        #expect(
            formatCodingUsageCostTrendPercent(
                CodingUsageCostTrend(currentCostUSD: 120, previousCostUSD: 100)) == "+20.0%")
        #expect(
            formatCodingUsageCostTrendPercent(
                CodingUsageCostTrend(currentCostUSD: 95, previousCostUSD: 100)) == "-5.0%")
        #expect(
            formatCodingUsageCostTrendPercent(
                CodingUsageCostTrend(currentCostUSD: 0, previousCostUSD: 0)) == "0.0%")
        #expect(
            formatCodingUsageCostTrendPercent(
                CodingUsageCostTrend(currentCostUSD: 100, previousCostUSD: 0)) == "+100.0%")
    }

    @Test("rounds cost trend direction to displayed precision")
    func roundsCostTrendDirectionToDisplayedPrecision() {
        #expect(
            CodingUsageCostTrend(currentCostUSD: 100.04, previousCostUSD: 100).direction == .flat)
        #expect(
            CodingUsageCostTrend(currentCostUSD: 99.96, previousCostUSD: 100).direction == .flat)
        #expect(CodingUsageCostTrend(currentCostUSD: 100.06, previousCostUSD: 100).direction == .up)
        #expect(
            CodingUsageCostTrend(currentCostUSD: 99.94, previousCostUSD: 100).direction == .down)
    }

    @Test("coerces rounded negative zero trend to positive zero")
    func coercesNegativeZeroTrendToPositiveZero() {
        let trend = CodingUsageCostTrend(currentCostUSD: 99.999, previousCostUSD: 100)

        #expect(trend.percent == 0)
        #expect(trend.percent.sign == .plus)
        #expect(trend.direction == .flat)
        #expect(formatCodingUsageCostTrendPercent(trend) == "0.0%")
    }

    @Test("placeholder builds a full thirty day zero grid per agent")
    func placeholderBuildsFullZeroGrid() {
        let calendar = gregorianUTC()
        let scope = CodingUsageDateScope(now: date(2026, 6, 18, 12), calendar: calendar)
        let report = CodingUsageReport.placeholder(scope: scope, agents: [.codex, .pi])

        #expect(report.state == .loading)
        #expect(report.agents.map(\.agent) == [.codex, .pi])
        for summary in report.agents {
            #expect(summary.dailyCounts.count == 30)
            #expect(summary.dailyCounts.first?.date == date(2026, 5, 20))
            #expect(summary.dailyCounts.last?.date == date(2026, 6, 18))
            #expect(summary.dailyCounts.allSatisfy { !$0.counts.hasUsage })
        }
    }

    @Test("token only counts are usage but not cost")
    func tokenOnlyCountsAreUsageButNotCost() {
        let counts = CodingTokenCounts(totalTokens: 10, costUSD: 0)

        #expect(counts.hasUsage)
        #expect(!counts.hasCost)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, _ costUSD: Double)
        -> CodingUsageDaySummary
    {
        CodingUsageDaySummary(
            date: date(year, month, day),
            counts: CodingTokenCounts(
                totalTokens: UInt64(costUSD * 1_000_000_000), costUSD: costUSD)
        )
    }
}
