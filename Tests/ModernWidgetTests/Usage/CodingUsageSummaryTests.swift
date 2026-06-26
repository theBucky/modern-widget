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

        let rows = summary.usageRows(now: now, calendar: calendar)

        #expect(rows.map(\.title) == ["Yesterday", "Today", "Weekly", "Monthly"])
        #expect(rows.map(\.counts.costUSD) == [2, 3, 5, 6])
        #expect(
            rows.map(\.counts.totalTokens) == [
                2_000_000_000,
                3_000_000_000,
                5_000_000_000,
                6_000_000_000,
            ])
    }

    @Test("summarizes today's report total across agents")
    func summarizesTodayReportTotalAcrossAgents() {
        let calendar = gregorianUTC()
        let now = date(2026, 6, 18, 12)
        let report = CodingUsageReport(
            generatedAt: now,
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

        let counts = report.todaySummary(now: now, calendar: calendar).counts

        #expect(counts.costUSD == 6)
        #expect(counts.totalTokens == 6_000_000_000)
    }

    @Test("summarizes today's cost trend across agents")
    func summarizesTodayCostTrendAcrossAgents() {
        let calendar = gregorianUTC()
        let now = date(2026, 6, 18, 12)
        let report = CodingUsageReport(
            generatedAt: now,
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

        let trend = report.todaySummary(now: now, calendar: calendar).costTrend

        #expect(trend.percent == 50)
        #expect(trend.direction == .up)
    }

    @Test("keeps chart days in source order")
    func keepsChartDaysInSourceOrder() {
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

        #expect(
            summary.chartDays(endingAt: now, calendar: calendar).map(\.date) == [
                date(2026, 6, 1),
                date(2026, 6, 17),
                date(2026, 6, 18),
            ])
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

    @Test("empty summary gets a thirty day chart window")
    func emptySummaryGetsChartWindow() {
        let calendar = gregorianUTC()
        let now = date(2026, 6, 18, 12)
        let days = CodingUsageAgentSummary(agent: .codex, dailyCounts: [])
            .chartDays(endingAt: now, calendar: calendar)

        #expect(days.count == 30)
        #expect(days.first?.date == date(2026, 5, 20))
        #expect(days.last?.date == date(2026, 6, 18))
        #expect(days.allSatisfy { !$0.counts.hasUsage })
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
