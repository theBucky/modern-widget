import SwiftUI

struct CodingUsageView: View {
    let store: CodingUsageStore

    var body: some View {
        VStack(spacing: PanelLayout.sectionSpacing) {
            CodingUsageTodayTotalSection(
                summary: store.report.todaySummary(now: reportDate),
                isLoading: isLoading
            )
            Divider()
            ForEach(store.report.agents, id: \.agent) { summary in
                agentSection(summary)
            }
        }
    }

    private func agentSection(_ summary: CodingUsageAgentSummary) -> some View {
        VStack(alignment: .leading, spacing: PanelLayout.contentSpacing) {
            HStack(spacing: 6) {
                Image(summary.agent.logoResourceName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)

                Text(summary.agent.title)
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: PanelLayout.sectionSpacing) {
                usageTable(for: summary)

                CodingUsageChart(
                    days: summary.chartDays(endingAt: reportDate),
                    isLoading: isLoading,
                    barColor: summary.agent.barColor
                )
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                .quaternary.opacity(0.25), in: .rect(cornerRadius: PanelLayout.cornerRadius))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func usageTable(for summary: CodingUsageAgentSummary) -> some View {
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

    private var isLoading: Bool {
        store.report.generatedAt == nil
    }

    private var reportDate: Date {
        store.report.generatedAt ?? .now
    }
}

extension CodingUsageAgent {
    fileprivate var logoResourceName: String {
        switch self {
        case .claude:
            return "ClaudeLogo"
        case .codex:
            return "CodexLogo"
        case .pi:
            return "PiLogo"
        }
    }

    fileprivate var barColor: Color {
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
