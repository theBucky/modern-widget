import SwiftUI

struct CodingUsageTodayTotalSection: View {
    let summary: CodingUsageTodaySummary

    var body: some View {
        HStack(alignment: .bottom) {
            CodingUsageCostTrendGroup(summary: summary)

            Spacer(minLength: 16)

            dateTokenGroup
                .layoutPriority(1)
        }
        // The numeric rolls and the layout share one transaction; per-text animations
        // leave the layout un-animated, snapping the fill and badge to the new width
        // mid-roll and hard-clipping the old string at the fill edge.
        .animation(.easeOut(duration: 0.5), value: summary)
    }

    private var dateTokenGroup: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(summary.date, format: .codingUsageDay)
            Text(summary.totals.totalTokens, format: .codingUsageTokens)
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct CodingUsageCostTrendGroup: View {
    let summary: CodingUsageTodaySummary

    var body: some View {
        HStack(alignment: .top, spacing: PanelLayout.contentSpacing) {
            totalCostText
            trendBadge
                .padding(.top, 7)  // optical inset against the 32pt cost line
        }
    }

    /// A gradient `foregroundStyle` composites the text within its tight layout bounds, which
    /// hard-clips the numeric roll blur, so the visible copy masks a fill oversized by
    /// `costTextOverdraw` while a hidden copy keeps the layout. `minimumScaleFactor` engages
    /// transiently while the roll interpolates width, so a hidden zero pins the composite to
    /// the full line height and the mask copy is proposed the composite width to scale in
    /// lockstep with the layout copy.
    private var totalCostText: some View {
        ZStack {
            Text(verbatim: "0")
                .font(costFont)
                .hidden()
            animatedCostText
                .opacity(0)
        }
        .overlay {
            Rectangle()
                .fill(totalCostStyle)
                .mask {
                    animatedCostText
                        .padding(costTextOverdraw)
                }
                .padding(-costTextOverdraw)
        }
        .accessibilityRepresentation {
            Text(summary.totals.costUSD, format: .codingUsageCost)
        }
    }

    private var animatedCostText: some View {
        Text(summary.totals.costUSD, format: .codingUsageCost)
            .font(costFont)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .contentTransition(.numericText(value: summary.totals.costUSD))
    }

    private var totalCostStyle: AnyShapeStyle {
        if !summary.totals.hasUsage {
            return AnyShapeStyle(.tertiary)
        }
        return AnyShapeStyle(
            LinearGradient(colors: [.primary, .secondary], startPoint: .top, endPoint: .bottom))
    }

    private var trendBadge: some View {
        Text(summary.costTrend, format: .codingUsageCostTrendPercent)
            .font(.caption.monospacedDigit().weight(.regular))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(trendColor, in: Capsule(style: .continuous))
            .contentTransition(.numericText(value: summary.costTrend.percent))
    }

    private var trendColor: Color {
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

private let costFont: Font = .system(size: 32, weight: .semibold, design: .rounded)

/// Extra render room around the cost text so the numeric roll blur never touches the fill edge.
private let costTextOverdraw: CGFloat = 12
