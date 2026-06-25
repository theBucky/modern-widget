import AppKit
import Charts
import SwiftUI

struct CodingUsageView: View {
    let store: CodingUsageStore

    var body: some View {
        VStack(spacing: 10) {
            CodingUsageTodayTotalSection(
                summary: store.report.todaySummary(now: reportDate),
                isFetching: isFetching
            )
            Divider()
            ForEach(store.report.agents, id: \.agent) { summary in
                agentSection(summary)
            }
        }
    }

    private var isFetching: Bool {
        store.report.generatedAt == nil
    }

    private func agentSection(_ summary: CodingUsageAgentSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let url = Bundle.main.url(
                    forResource: summary.agent.logoResourceName, withExtension: "pdf"),
                    let image = NSImage(contentsOf: url)
                {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                }

                Text(summary.agent.title)
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 12) {
                usageTable(summary)

                CodingUsageChart(
                    days: summary.chartDays(endingAt: reportDate),
                    isFetching: isFetching,
                    barColor: barColor(for: summary.agent)
                )
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func usageTable(_ summary: CodingUsageAgentSummary) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            ForEach(summary.usageRows(now: reportDate), id: \.title) { row in
                GridRow {
                    Text(row.title)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    CodingUsageValueText(counts: row.counts, isFetching: isFetching)
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

    private func barColor(for agent: CodingUsageAgent) -> Color {
        switch agent {
        case .claude:
            return Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
        case .codex:
            return Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)
        case .pi:
            return .accentColor
        }
    }
}

private struct CodingUsageTodayTotalSection: View {
    let summary: CodingUsageTodaySummary
    let isFetching: Bool

    @State private var displayedCostUSD = 0.0

    var body: some View {
        HStack(alignment: .bottom) {
            costTrendGroup

            Spacer(minLength: 16)

            dateTokenGroup
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            updateDisplayedCost(animated: !isFetching)
        }
        .onChange(of: targetCostUSD) {
            updateDisplayedCost(animated: true)
        }
    }

    private var costTrendGroup: some View {
        CodingUsageCostTrendGroup(
            costUSD: displayedCostUSD,
            costTrend: summary.costTrend,
            hasUsage: summary.counts.hasUsage,
            isFetching: isFetching
        )
    }

    private var dateTokenGroup: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(dateText)
            Text(formatCodingUsageTokens(summary.counts.totalTokens))
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var dateText: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: summary.date)
        return String(
            format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    private var targetCostUSD: Double {
        isFetching ? 0 : summary.counts.costUSD
    }

    private func updateDisplayedCost(animated: Bool) {
        if animated, !isFetching {
            withAnimation(.easeOut(duration: Self.costAnimationDuration)) {
                displayedCostUSD = targetCostUSD
            }
            return
        }

        displayedCostUSD = targetCostUSD
    }

    private static let costAnimationDuration = 1.0
}

private struct CodingUsageCostTrendGroup: View, @MainActor Animatable {
    var costUSD: Double
    let costTrend: CodingUsageCostTrend
    let hasUsage: Bool
    let isFetching: Bool

    var animatableData: Double {
        get { costUSD }
        set { costUSD = newValue }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            totalCostText
            trendBadge
                .padding(.top, 7)
        }
    }

    @ViewBuilder
    private var totalCostText: some View {
        let text = Text(isFetching ? "fetching" : formatCodingUsageCost(costUSD))
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .monospacedDigit()

        if isFetching {
            text.foregroundStyle(.secondary)
        } else if !hasUsage {
            text.foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        } else {
            text.foregroundStyle(
                LinearGradient(
                    colors: [Color(nsColor: .textColor), Color(nsColor: .secondaryLabelColor)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
        }
    }

    private var trendBadge: some View {
        Text(isFetching ? "fetching" : formatCodingUsageCostTrendMagnitude(costTrend))
            .font(.caption.monospacedDigit())
            .fontWeight(.regular)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(trendColor, in: Capsule(style: .continuous))
            .contentTransition(.numericText(value: costTrend.percent))
    }

    private var trendColor: Color {
        if isFetching {
            return .secondary
        }

        switch costTrend.direction {
        case .up:
            return Color(red: 0, green: 128 / 255, blue: 9 / 255)
        case .down:
            return Color(red: 182 / 255, green: 68 / 255, blue: 0)
        case .flat:
            return Color(nsColor: .systemGray)
        }
    }
}

private struct CodingUsageChart: View {
    let days: [CodingUsageDaySummary]
    let isFetching: Bool
    let barColor: Color

    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(days, id: \.date) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Cost", barHeightValue(for: day)),
                    width: .ratio(0.7)
                )
                .foregroundStyle(
                    isFetching ? Color.secondary.opacity(0.18) : barColor)
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
        .chartYScale(domain: 0...chartUpperBound)
        .frame(height: 58)
        .frame(maxWidth: .infinity)
    }

    private var maxCost: Double {
        days.map(\.counts.costUSD).max() ?? 0
    }

    private var minimumVisibleCost: Double {
        maxCost > 0 ? maxCost * 0.08 : 0.08
    }

    private var chartUpperBound: Double {
        if isFetching {
            return 1
        }
        return max(maxCost, minimumVisibleCost)
    }

    private func barHeightValue(for day: CodingUsageDaySummary) -> Double {
        if isFetching {
            return 1
        }
        guard day.counts.hasUsage else {
            return 0
        }
        return max(day.counts.costUSD, minimumVisibleCost)
    }

    private var selectedDay: CodingUsageDaySummary? {
        guard let selectedDate else {
            return nil
        }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private func chartHoverAnnotation(_ day: CodingUsageDaySummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                .foregroundStyle(Color.secondary)
            CodingUsageValueText(
                counts: day.counts,
                isFetching: isFetching
            )
        }
        .font(.caption2.monospacedDigit())
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: .rect(cornerRadius: 4))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }
}

private struct CodingUsageValueText: View {
    let counts: CodingTokenCounts
    let isFetching: Bool

    var body: some View {
        if isFetching {
            Text("fetching")
                .foregroundColor(Self.costColor)
        } else {
            Text("\(tokenText) / \(costText)")
        }
    }

    private var tokenText: Text {
        Text(formatCodingUsageTokens(counts.totalTokens))
            .fontWeight(.regular)
            .foregroundColor(.secondary)
    }

    private var costText: Text {
        Text(formatCodingUsageCost(counts.costUSD))
            .fontWeight(.semibold)
            .foregroundColor(counts.hasUsage ? Self.costColor : Color(nsColor: .tertiaryLabelColor))
    }

    private static let costColor = Color(nsColor: .textColor)
}
