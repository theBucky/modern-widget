import SwiftUI

struct CodingUsageTodayTotalSection: View {
    let summary: CodingUsageTodaySummary
    let isLoading: Bool

    @State private var displayedCostUSD = 0.0
    @State private var isTrendVisible = false

    var body: some View {
        HStack(alignment: .bottom) {
            CodingUsageCostTrendGroup(
                costUSD: displayedCostUSD,
                costTrend: summary.costTrend,
                hasUsage: summary.counts.hasUsage,
                isLoading: isLoading,
                isTrendVisible: isTrendVisible
            )

            Spacer(minLength: 16)

            dateTokenGroup
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: animationState) {
            await animateTotal()
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

    private var animationState: CodingUsageTodayTotalAnimationState {
        CodingUsageTodayTotalAnimationState(
            isLoading: isLoading,
            costUSD: summary.counts.costUSD
        )
    }

    private func animateTotal() async {
        isTrendVisible = false

        if isLoading {
            displayedCostUSD = 0
            return
        }

        withAnimation(.easeOut(duration: Self.costAnimationDuration)) {
            displayedCostUSD = summary.counts.costUSD
        }

        try? await Task.sleep(for: .seconds(Self.costAnimationDuration))
        if Task.isCancelled {
            return
        }

        withAnimation(.easeOut(duration: Self.trendFadeDuration)) {
            isTrendVisible = true
        }
    }

    private static let costAnimationDuration = 1.0
    private static let trendFadeDuration = 0.2
}

private struct CodingUsageTodayTotalAnimationState: Equatable {
    let isLoading: Bool
    let costUSD: Double
}

private struct CodingUsageCostTrendGroup: View, @MainActor Animatable {
    var costUSD: Double
    let costTrend: CodingUsageCostTrend
    let hasUsage: Bool
    let isLoading: Bool
    let isTrendVisible: Bool

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
            text.foregroundStyle(.tertiary)
        } else {
            text.foregroundStyle(
                LinearGradient(
                    colors: [.primary, .secondary],
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
            .opacity(isTrendVisible ? 1 : 0)
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
            return .gray
        }
    }
}
