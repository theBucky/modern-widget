import Foundation
import Testing

@testable import ModernWidget

@Suite("Coding usage summary")
struct CodingUsageSummaryTests {
    @Test("summarizes cost windows and chart days")
    func summarizesCostWindowsAndChartDays() {
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
            summary.costRows(now: now, calendar: calendar) == [
                CodingUsageCostRow(title: "Yesterday", costUSD: 2),
                CodingUsageCostRow(title: "Today", costUSD: 3),
                CodingUsageCostRow(title: "Weekly", costUSD: 5),
                CodingUsageCostRow(title: "Monthly", costUSD: 6),
            ])
        #expect(
            summary.chartDays(endingAt: now, calendar: calendar).map(\.date) == [
                date(2026, 6, 1),
                date(2026, 6, 17),
                date(2026, 6, 18),
            ])
        #expect(formatCodingUsageCost(0.0042) == "$0.0042")
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
            counts: CodingTokenCounts(costUSD: costUSD)
        )
    }
}
