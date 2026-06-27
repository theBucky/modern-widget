import AppKit
import SwiftUI

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
