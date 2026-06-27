import AppKit
import Charts
import SwiftUI

struct CodingUsageAgentSection: View {
    let summary: CodingUsageAgentSummary
    let reportDate: Date
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PanelLayout.contentSpacing) {
            HStack(spacing: PanelLayout.contentSpacing) {
                CodingUsageLogoImage(agent: summary.agent)

                Text(summary.agent.title)
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: PanelLayout.sectionSpacing) {
                usageTable

                CodingUsageChart(
                    days: summary.chartDays(endingAt: reportDate),
                    isLoading: isLoading,
                    barColor: summary.agent.barColor
                )
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PanelLayout.contentSpacing)
            .background(
                .quaternary.opacity(0.25), in: .rect(cornerRadius: PanelLayout.cornerRadius))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usageTable: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: PanelLayout.contentSpacing,
            verticalSpacing: PanelLayout.tightSpacing
        ) {
            ForEach(summary.usageRows(now: reportDate)) { row in
                GridRow {
                    Text(row.title)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    CodingUsageValueText(counts: row.counts, isLoading: isLoading)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity)
    }
}

private struct CodingUsageLogoImage: View {
    let agent: CodingUsageAgent

    var body: some View {
        Image(nsImage: NSImage(contentsOf: logoURL)!)
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }

    private var logoURL: URL {
        Bundle.main.resourceURL!
            .appendingPathComponent("modern-widget_ModernWidget.bundle")
            .appendingPathComponent("Assets.xcassets")
            .appendingPathComponent("\(agent.logoResourceName).imageset")
            .appendingPathComponent("\(agent.logoResourceName).pdf")
    }
}

struct CodingUsageTodayTotalSection: View {
    let summary: CodingUsageTodaySummary
    let isLoading: Bool

    @State private var displayedCostUSD = 0.0

    var body: some View {
        HStack(alignment: .bottom) {
            CodingUsageCostTrendGroup(
                costUSD: displayedCostUSD,
                costTrend: summary.costTrend,
                hasUsage: summary.counts.hasUsage,
                isLoading: isLoading
            )

            Spacer(minLength: 16)

            dateTokenGroup
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            updateDisplayedCost(animated: !isLoading)
        }
        .onChange(of: targetCostUSD) {
            updateDisplayedCost(animated: true)
        }
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
        let calendar = Calendar.current
        return String(
            format: "%04d-%02d-%02d",
            calendar.component(.year, from: summary.date),
            calendar.component(.month, from: summary.date),
            calendar.component(.day, from: summary.date)
        )
    }

    private var targetCostUSD: Double {
        isLoading ? 0 : summary.counts.costUSD
    }

    private func updateDisplayedCost(animated: Bool) {
        if animated, !isLoading {
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
    let isLoading: Bool

    var animatableData: Double {
        get { costUSD }
        set { costUSD = newValue }
    }

    var body: some View {
        HStack(alignment: .top, spacing: PanelLayout.contentSpacing) {
            totalCostText
            trendBadge
                .padding(.top, 7)
        }
    }

    @ViewBuilder
    private var totalCostText: some View {
        let text = Text(isLoading ? "loading" : formatCodingUsageCost(costUSD))
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .monospacedDigit()

        if isLoading {
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
        Text(isLoading ? "loading" : formatCodingUsageCostTrendPercent(costTrend))
            .font(.caption.monospacedDigit())
            .fontWeight(.regular)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(trendColor, in: Capsule(style: .continuous))
            .contentTransition(.numericText(value: costTrend.percent))
    }

    private var trendColor: Color {
        if isLoading {
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
    let isLoading: Bool
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
                .foregroundStyle(isLoading ? Color.secondary.opacity(0.18) : barColor)
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
        if isLoading {
            return 1
        }
        return max(maxCost, minimumVisibleCost)
    }

    private func barHeightValue(for day: CodingUsageDaySummary) -> Double {
        if isLoading {
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
                isLoading: isLoading
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
    let isLoading: Bool

    var body: some View {
        if isLoading {
            Text("loading")
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

private extension CodingUsageAgent {
    var barColor: Color {
        switch self {
        case .claude:
            return Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
        case .codex:
            return Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)
        case .pi:
            return .accentColor
        }
    }
}
