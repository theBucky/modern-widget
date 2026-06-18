import Charts
import SwiftUI

struct CodingUsageView: View {
    let store: CodingUsageStore

    private enum Layout {
        static let spacing: CGFloat = 10
        static let rowSpacing: CGFloat = 6
        static let blockPadding: CGFloat = 8
        static let cornerRadius: CGFloat = 6
        static let labelWidth: CGFloat = 64
    }

    var body: some View {
        VStack(spacing: Layout.spacing) {
            ForEach(store.report.agents, id: \.agent) { summary in
                agentSection(summary)
            }
        }
    }

    private var isFetching: Bool {
        store.report.generatedAt == nil
    }

    private func agentSection(_ summary: CodingUsageAgentSummary) -> some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            Text(summary.agent.title)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                amountTable(summary)
                usageChart(summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Layout.blockPadding)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: Layout.cornerRadius))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func amountTable(_ summary: CodingUsageAgentSummary) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            ForEach(amountRows(summary), id: \.title) { row in
                GridRow {
                    Text(row.title)
                        .foregroundStyle(.secondary)
                        .frame(width: Layout.labelWidth, alignment: .leading)
                    Text(isFetching ? "fetching" : formatCost(row.costUSD))
                        .fontWeight(.semibold)
                        .foregroundStyle(isFetching || row.costUSD > 0 ? .primary : .tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity)
    }

    private func usageChart(_ summary: CodingUsageAgentSummary) -> some View {
        Chart(chartDays(summary), id: \.date) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Cost", isFetching ? 1 : day.counts.costUSD),
                width: .ratio(0.7)
            )
            .foregroundStyle(
                isFetching ? Color.secondary.opacity(0.18) : Color.accentColor.opacity(0.8))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
    }

    private func amountRows(_ summary: CodingUsageAgentSummary) -> [CodingUsageAmountRow] {
        let calendar = Calendar.current
        let now = reportDate
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        let month = calendar.dateInterval(of: .month, for: now)!

        return [
            CodingUsageAmountRow(
                title: "Yesterday",
                costUSD: cost(in: DateInterval(start: yesterdayStart, end: todayStart), summary)
            ),
            CodingUsageAmountRow(
                title: "Today",
                costUSD: cost(in: DateInterval(start: todayStart, end: tomorrowStart), summary)
            ),
            CodingUsageAmountRow(title: "Weekly", costUSD: cost(in: week, summary)),
            CodingUsageAmountRow(title: "Monthly", costUSD: cost(in: month, summary)),
        ]
    }

    private func cost(in interval: DateInterval, _ summary: CodingUsageAgentSummary) -> Double {
        summary.dailyCounts.reduce(0) { total, day in
            guard day.date >= interval.start && day.date < interval.end else {
                return total
            }
            return total + day.counts.costUSD
        }
    }

    private func chartDays(_ summary: CodingUsageAgentSummary) -> [CodingUsageDaySummary] {
        if !summary.dailyCounts.isEmpty {
            return Array(summary.dailyCounts.suffix(30))
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: reportDate)
        let start = calendar.date(byAdding: .day, value: -29, to: today)!

        return (0..<30).map { offset in
            CodingUsageDaySummary(
                date: calendar.date(byAdding: .day, value: offset, to: start)!,
                counts: CodingTokenCounts()
            )
        }
    }

    private var reportDate: Date {
        store.report.generatedAt ?? .now
    }

    private func formatCost(_ cost: Double) -> String {
        if cost <= 0 {
            return "$0.00"
        }
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
    }
}

private struct CodingUsageAmountRow {
    let title: String
    let costUSD: Double
}
