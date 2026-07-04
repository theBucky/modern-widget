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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(alignment: .trendBadgeTop, spacing: PanelLayout.contentSpacing) {
            totalCostText
                .alignmentGuide(.trendBadgeTop) { $0.height * trendBadgeTopInsetRatio }
            trendBadge
        }
    }

    /// A gradient `foregroundStyle` composites the text within its tight layout bounds, which
    /// hard-clips the numeric roll blur. A hidden copy keeps the layout while the visible copy
    /// masks an oversized fill, giving the transition overdraw room on every side.
    private var totalCostText: some View {
        animatedCostText
            .opacity(0)
            .overlay {
                Rectangle()
                    .fill(totalCostStyle)
                    .padding(-costTextOverdraw)
                    .mask {
                        animatedCostText
                            .fixedSize()
                    }
            }
            .accessibilityRepresentation {
                Text(summary.counts.costUSD, format: .codingUsageCost)
            }
    }

    private var animatedCostText: some View {
        Text(summary.counts.costUSD, format: .codingUsageCost)
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .contentTransition(.numericText(value: summary.counts.costUSD))
            .animation(.easeOut(duration: 0.5), value: summary.counts.costUSD)
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
            .animation(.easeOut(duration: 0.5), value: summary.costTrend.percent)
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

/// Optical top inset tuned against the 32pt cost text, expressed as a fraction of the rendered
/// line height so it tracks `minimumScaleFactor` shrinkage.
private let trendBadgeTopInsetRatio: CGFloat = 7.0 / 38.0

/// Extra render room around the cost text so the numeric roll blur never touches the fill edge.
private let costTextOverdraw: CGFloat = 12

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
