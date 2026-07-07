import SwiftUI

struct CodingUsageTodayTotalSection: View {
    let summary: CodingUsageTodaySummary

    #if DEBUG
        @State private var replayToken = 0
        @State private var replaySummary: CodingUsageTodaySummary?
    #endif

    var body: some View {
        #if DEBUG
            let visibleSummary = replaySummary ?? summary
        #else
            let visibleSummary = summary
        #endif

        HStack(alignment: .bottom) {
            CodingUsageCostTrendGroup(summary: visibleSummary)

            Spacer(minLength: 16)

            trailingGroup(summary: visibleSummary)
                .layoutPriority(1)
        }
        // The numeric rolls and the layout share one transaction; per-text animations
        // leave the layout un-animated, snapping the fill and badge to the new width
        // mid-roll and hard-clipping the old string at the fill edge.
        .animation(.easeOut(duration: 0.5), value: visibleSummary)
    }

    private func trailingGroup(summary: CodingUsageTodaySummary) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            #if DEBUG
                replayButton
            #endif

            dateTokenGroup(summary: summary)
        }
    }

    private func dateTokenGroup(summary: CodingUsageTodaySummary) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(summary.date, format: .codingUsageDay)
            Text(summary.counts.totalTokens, format: .codingUsageTokens)
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.secondary)
    }

    #if DEBUG
        private var replayButton: some View {
            Button {
                replaySummaryAnimation()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Replay summary animation")
            .accessibilityLabel("Replay summary animation")
        }

        private func replaySummaryAnimation() {
            replayToken += 1
            let token = replayToken
            replaySummary = Self.replayStartSummary(for: summary)

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard token == replayToken else {
                    return
                }

                replaySummary = nil
            }
        }

        private static func replayStartSummary(for summary: CodingUsageTodaySummary)
            -> CodingUsageTodaySummary
        {
            var counts = summary.counts
            let targetCostUSD = max(summary.counts.costUSD, 0.15)
            counts.costUSD = max(targetCostUSD * 0.35, 0.01)
            counts.totalTokens = max(summary.counts.totalTokens / 3, 1)

            return CodingUsageTodaySummary(
                date: summary.date,
                counts: counts,
                costTrend: CodingUsageCostTrend(
                    currentCostUSD: counts.costUSD,
                    previousCostUSD: counts.costUSD * 2
                )
            )
        }
    #endif
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
            Text(summary.counts.costUSD, format: .codingUsageCost)
        }
    }

    private var animatedCostText: some View {
        Text(summary.counts.costUSD, format: .codingUsageCost)
            .font(costFont)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .contentTransition(.numericText(value: summary.counts.costUSD))
    }

    private var totalCostStyle: AnyShapeStyle {
        if !summary.counts.hasUsage {
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
