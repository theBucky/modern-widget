import SwiftUI

struct CodingUsageTodayTotalSection: View {
    let summary: CodingUsageTodaySummary
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .bottom) {
            CodingUsageCostTrendGroup(summary: summary, isLoading: isLoading)

            Spacer(minLength: 16)

            dateTokenGroup
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

private struct CodingUsageCostTrendGroup: View {
    let summary: CodingUsageTodaySummary
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .trendBadgeTop, spacing: PanelLayout.contentSpacing) {
            totalCostText
                .alignmentGuide(.trendBadgeTop) { $0.height * trendBadgeTopInsetRatio }
            trendBadge
        }
    }

    private var totalCostText: some View {
        Text(isLoading ? "loading" : formatCodingUsageCost(summary.counts.costUSD))
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .foregroundStyle(totalCostStyle)
            .contentTransition(.numericText(value: summary.counts.costUSD))
            .animation(.easeOut(duration: 0.5), value: summary.counts.costUSD)
    }

    private var totalCostStyle: AnyShapeStyle {
        if isLoading {
            return AnyShapeStyle(.secondary)
        }
        if !summary.counts.hasUsage {
            return AnyShapeStyle(.tertiary)
        }
        return AnyShapeStyle(
            LinearGradient(colors: [.primary, .secondary], startPoint: .top, endPoint: .bottom))
    }

    private var trendBadge: some View {
        Text(isLoading ? "loading" : formatCodingUsageCostTrendPercent(summary.costTrend))
            .font(.caption.monospacedDigit().weight(.regular))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(trendColor, in: Capsule(style: .continuous))
            .contentTransition(.numericText(value: summary.costTrend.percent))
            .animation(.easeOut(duration: 0.5), value: summary.costTrend.percent)
    }

    private var trendColor: Color {
        if isLoading {
            return .secondary
        }

        switch summary.costTrend.direction {
        case .up:
            return PanelColor.statusGreen
        case .down:
            return PanelColor.statusOrange
        case .flat:
            return .gray
        }
    }
}

/// Optical top inset tuned against the 32pt cost text, expressed as a fraction of the rendered
/// line height so it tracks `minimumScaleFactor` shrinkage.
private let trendBadgeTopInsetRatio: CGFloat = 7.0 / 38.0

extension VerticalAlignment {
    private enum TrendBadgeTop: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[.top]
        }
    }

    /// Anchors the trend badge top partway down the cost text so the two stay optically
    /// coupled as the cost scales.
    fileprivate static let trendBadgeTop = VerticalAlignment(TrendBadgeTop.self)
}
