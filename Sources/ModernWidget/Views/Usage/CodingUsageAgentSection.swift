import SwiftUI

struct CodingUsageAgentSection: View {
    let summary: CodingUsageAgentSummary
    let reportDate: Date
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PanelLayout.contentSpacing) {
            HStack(spacing: PanelLayout.contentSpacing) {
                Image(summary.agent.logoResourceName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)

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

private extension CodingUsageAgent {
    var logoResourceName: String {
        switch self {
        case .claude:
            return "ClaudeLogo"
        case .codex:
            return "CodexLogo"
        case .pi:
            return "PiLogo"
        }
    }

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
