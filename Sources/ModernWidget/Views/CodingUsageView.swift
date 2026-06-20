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
        static let logoSize: CGFloat = 14
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
            HStack(spacing: 6) {
                CodingUsageAgentLogo(agent: summary.agent, size: Layout.logoSize)

                Text(summary.agent.title)
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                amountTable(summary)
                CodingUsageChart(
                    days: summary.chartDays(endingAt: reportDate),
                    isFetching: isFetching
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Layout.blockPadding)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: Layout.cornerRadius))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func amountTable(_ summary: CodingUsageAgentSummary) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            ForEach(summary.costRows(now: reportDate), id: \.title) { row in
                GridRow {
                    Text(row.title)
                        .foregroundStyle(.secondary)
                        .frame(width: Layout.labelWidth, alignment: .leading)
                    usageCostText(row.costUSD, isFetching: isFetching)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity)
    }

    private var reportDate: Date {
        store.report.generatedAt ?? .now
    }
}

private struct CodingUsageChart: View {
    let days: [CodingUsageDaySummary]
    let isFetching: Bool

    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(days, id: \.date) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Cost", isFetching ? 1 : day.counts.costUSD),
                    width: .ratio(0.7)
                )
                .foregroundStyle(
                    isFetching ? Color.secondary.opacity(0.18) : Color.accentColor.opacity(0.8))
            }

            if let selectedDay {
                RuleMark(x: .value("Selected Day", selectedDay.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .annotation(
                        position: .top, spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        chartHoverAnnotation(selectedDay)
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
    }

    private var selectedDay: CodingUsageDaySummary? {
        guard let selectedDate else {
            return nil
        }
        return days.first { day in
            Calendar.current.dateInterval(of: .day, for: day.date)!.contains(selectedDate)
        }
    }

    private func chartHoverAnnotation(_ day: CodingUsageDaySummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                .foregroundStyle(.secondary)
            usageCostText(day.counts.costUSD, isFetching: isFetching)
        }
        .font(.caption2.monospacedDigit())
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: .rect(cornerRadius: 4))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }
}

private func usageCostText(_ cost: Double, isFetching: Bool) -> Text {
    Text(isFetching ? "fetching" : formatCodingUsageCost(cost))
        .foregroundStyle(isFetching || cost > 0 ? .primary : .tertiary)
}
