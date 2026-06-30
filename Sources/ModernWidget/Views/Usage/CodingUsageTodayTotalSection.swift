import SwiftUI

struct CodingUsageTodayTotalSection: View {
    let summary: CodingUsageTodaySummary
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .bottom) {
            if isLoading {
                CodingUsageCostTrendGroup(
                    display: .loading,
                    costTrend: summary.costTrend,
                    hasUsage: summary.counts.hasUsage
                )
            } else {
                CodingUsageLoadedCostTrendGroup(summary: summary)
            }

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

private struct CodingUsageLoadedCostTrendGroup: View {
    let summary: CodingUsageTodaySummary

    @State private var display: CodingUsageTodayTotalDisplay

    init(summary: CodingUsageTodaySummary) {
        self.summary = summary
        _display = State(initialValue: .initial(costUSD: summary.counts.costUSD))
    }

    var body: some View {
        CodingUsageCostTrendGroup(
            display: display,
            costTrend: summary.costTrend,
            hasUsage: summary.counts.hasUsage
        )
        .task(id: summary.counts.costUSD) {
            await animateTotal(to: summary.counts.costUSD)
        }
    }

    private static let costAnimationDuration = 1.0
    private static let trendFadeDuration = 0.2

    private func animateTotal(to costUSD: Double) async {
        guard display.costUSD != costUSD else {
            display = .settled(costUSD: costUSD)
            return
        }

        display = .entering(costUSD: display.costUSD)
        withAnimation(.easeOut(duration: Self.costAnimationDuration)) {
            display = .entering(costUSD: costUSD)
        }

        try? await Task.sleep(for: .seconds(Self.costAnimationDuration))
        guard !Task.isCancelled else {
            return
        }

        withAnimation(.easeOut(duration: Self.trendFadeDuration)) {
            display = .settled(costUSD: costUSD)
        }
    }
}

private enum CodingUsageTodayTotalDisplay {
    case loading
    case entering(costUSD: Double)
    case settled(costUSD: Double)

    /// Already-zero totals settle immediately; a real total counts up from zero.
    static func initial(costUSD: Double) -> Self {
        costUSD == 0 ? .settled(costUSD: costUSD) : .entering(costUSD: 0)
    }

    var costUSD: Double {
        switch self {
        case .loading:
            return 0
        case let .entering(costUSD), let .settled(costUSD):
            return costUSD
        }
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var showsTrendBadge: Bool {
        switch self {
        case .loading, .settled:
            return true
        case .entering:
            return false
        }
    }

    func withCostUSD(_ costUSD: Double) -> Self {
        switch self {
        case .loading:
            return .loading
        case .entering:
            return .entering(costUSD: costUSD)
        case .settled:
            return .settled(costUSD: costUSD)
        }
    }
}

private struct CodingUsageCostTrendGroup: View, @MainActor Animatable {
    var display: CodingUsageTodayTotalDisplay
    let costTrend: CodingUsageCostTrend
    let hasUsage: Bool

    var animatableData: Double {
        get { display.costUSD }
        set { display = display.withCostUSD(newValue) }
    }

    var body: some View {
        HStack(alignment: .trendBadgeTop, spacing: PanelLayout.contentSpacing) {
            totalCostText
                .alignmentGuide(.trendBadgeTop) { $0.height * trendBadgeTopInsetRatio }
            trendBadge
        }
    }

    private var totalCostText: some View {
        Text(display.isLoading ? "loading" : formatCodingUsageCost(display.costUSD))
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .foregroundStyle(totalCostStyle)
    }

    private var totalCostStyle: AnyShapeStyle {
        if display.isLoading {
            return AnyShapeStyle(.secondary)
        }
        if !hasUsage {
            return AnyShapeStyle(.tertiary)
        }
        return AnyShapeStyle(
            LinearGradient(colors: [.primary, .secondary], startPoint: .top, endPoint: .bottom))
    }

    private var trendBadge: some View {
        Text(display.isLoading ? "loading" : formatCodingUsageCostTrendPercent(costTrend))
            .font(.caption.monospacedDigit().weight(.regular))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(trendColor, in: Capsule(style: .continuous))
            .contentTransition(.numericText(value: costTrend.percent))
            .opacity(display.showsTrendBadge ? 1 : 0)
    }

    private var trendColor: Color {
        if display.isLoading {
            return .secondary
        }

        switch costTrend.direction {
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
