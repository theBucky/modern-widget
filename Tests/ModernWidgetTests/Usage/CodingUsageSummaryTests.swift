import Foundation
import Testing

@testable import ModernWidget

@Suite("Coding usage summary")
struct CodingUsageSummaryTests {
    @Test("summarizes usage windows")
    func summarizesUsageWindows() throws {
        let calendar = gregorianUTC()
        let now = date(2026, 6, 18, 12)
        let scope = CodingUsageDateScope(now: now, calendar: calendar)
        let presentation = CodingUsagePresentation(
            report: CodingUsageReport(
                state: .loaded(generatedAt: now),
                agents: [
                    CodingUsageAgentSummary(
                        agent: .claude,
                        dailyCounts: [
                            day(2026, 6, 1, 1),
                            day(2026, 6, 17, 2),
                            day(2026, 6, 18, 3),
                        ]
                    )
                ]
            ),
            scope: scope,
            enabledAgents: [.claude]
        )

        let totals = try #require(presentation.sections.first?.periodTotals)

        #expect(totals.map(\.period) == [.today, .yesterday, .last7Days, .last30Days])
        #expect(totals.map(\.counts.costUSD) == [3, 2, 5, 6])
        #expect(
            totals.map(\.counts.totalTokens) == [
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
        let presentation = CodingUsagePresentation(
            report: CodingUsageReport(
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
            ),
            scope: CodingUsageDateScope(now: now, calendar: calendar),
            enabledAgents: Set(CodingUsageAgent.allCases)
        )

        let counts = presentation.today.counts

        #expect(counts.costUSD == 6)
        #expect(counts.totalTokens == 6_000_000_000)
    }

    @Test("summarizes today's cost trend across agents")
    func summarizesTodayCostTrendAcrossAgents() {
        let calendar = gregorianUTC()
        let now = date(2026, 6, 18, 12)
        let presentation = CodingUsagePresentation(
            report: CodingUsageReport(
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
            ),
            scope: CodingUsageDateScope(now: now, calendar: calendar),
            enabledAgents: Set(CodingUsageAgent.allCases)
        )

        let trend = presentation.today.costTrend

        #expect(trend.percent == 50)
        #expect(trend.direction == .up)
    }

    @Test("shows only enabled agents in stable order, filling a missing one with a zero grid")
    func showsOnlyEnabledAgentsInStableOrder() throws {
        let now = date(2026, 6, 18, 12)
        let presentation = CodingUsagePresentation(
            report: CodingUsageReport(
                state: .loaded(generatedAt: now),
                agents: [
                    CodingUsageAgentSummary(agent: .claude, dailyCounts: [day(2026, 6, 18, 1)]),
                    CodingUsageAgentSummary(agent: .codex, dailyCounts: [day(2026, 6, 18, 2)]),
                ]
            ),
            scope: CodingUsageDateScope(now: now, calendar: gregorianUTC()),
            enabledAgents: [.pi, .claude]
        )

        let claude = try #require(presentation.sections.first)
        let pi = try #require(presentation.sections.last)

        #expect(!presentation.isLoading)
        #expect(presentation.sections.map(\.agent) == [.claude, .pi])
        #expect(claude.periodTotals.last?.counts.costUSD == 1)
        #expect(pi.chartDays.map(\.date) == [date(2026, 6, 18)])
        #expect(pi.periodTotals.allSatisfy { !$0.counts.hasUsage })
    }

    @Test("formats small costs with four decimals")
    func formatsSmallCostsWithFourDecimals() {
        #expect(CodingUsageCostFormat().format(0.0042) == "$0.0042")
    }

    @Test("formats usage day in the supplied local time zone")
    func formatsUsageDayInSuppliedLocalTimeZone() {
        let timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let localMidnight = calendar.date(
            from: DateComponents(timeZone: timeZone, year: 2026, month: 6, day: 18)
        )!

        #expect(CodingUsageDayFormat(timeZone: timeZone).format(localMidnight) == "2026-06-18")
    }

    @Test("formats token counts with compact units")
    func formatsTokenCountsWithCompactUnits() {
        #expect(CodingUsageTokenFormat().format(999) == "999.0 tokens")
        #expect(CodingUsageTokenFormat().format(1_200) == "1.2K tokens")
        #expect(CodingUsageTokenFormat().format(999_950) == "1.0M tokens")
        #expect(CodingUsageTokenFormat().format(12_300_000_000) == "12.3B tokens")
        #expect(CodingUsageTokenFormat().format(1_200_000_000_000) == "1.2T tokens")
    }

    @Test("token unit promotes to the next unit when rounding crosses a thousand")
    func tokenUnitPromotionBoundaries() {
        #expect(CodingUsageTokenFormat().format(999_949) == "999.9K tokens")
        #expect(CodingUsageTokenFormat().format(999_950) == "1.0M tokens")
        #expect(CodingUsageTokenFormat().format(999_949_999) == "999.9M tokens")
        #expect(CodingUsageTokenFormat().format(999_950_000) == "1.0B tokens")
    }

    @Test("formats cost trend percent")
    func formatsCostTrendPercent() {
        #expect(
            CodingUsageCostTrendPercentFormat().format(
                CodingUsageCostTrend(currentCostUSD: 120, previousCostUSD: 100)) == "+20.0%")
        #expect(
            CodingUsageCostTrendPercentFormat().format(
                CodingUsageCostTrend(currentCostUSD: 95, previousCostUSD: 100)) == "-5.0%")
        #expect(
            CodingUsageCostTrendPercentFormat().format(
                CodingUsageCostTrend(currentCostUSD: 0, previousCostUSD: 0)) == "0.0%")
        #expect(
            CodingUsageCostTrendPercentFormat().format(
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
        #expect(CodingUsageCostTrendPercentFormat().format(trend) == "0.0%")
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
