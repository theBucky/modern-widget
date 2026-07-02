import SwiftUI

struct CodingUsageView: View {
    let store: CodingUsageStore

    var body: some View {
        let report = store.report
        let (isLoading, referenceDate): (Bool, Date) =
            switch report.state {
            case .loading: (true, Date.now)
            case .loaded(let generatedAt): (false, generatedAt)
            }
        let scope = CodingUsageDateScope(now: referenceDate)

        VStack(spacing: PanelLayout.sectionSpacing) {
            CodingUsageTodayTotalSection(
                summary: report.todaySummary(in: scope),
                isLoading: isLoading
            )
            Divider()
            ForEach(report.agents, id: \.agent) { summary in
                AgentUsageSection(summary: summary, scope: scope, isLoading: isLoading)
            }
        }
    }
}

private struct AgentUsageSection: View {
    let summary: CodingUsageAgentSummary
    let scope: CodingUsageDateScope
    let isLoading: Bool

    var body: some View {
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
                usageTable

                CodingUsageChart(
                    days: summary.dailyCounts,
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

    private var usageTable: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: PanelLayout.contentSpacing,
            verticalSpacing: PanelLayout.tightSpacing
        ) {
            ForEach(summary.usageRows(in: scope)) { row in
                GridRow {
                    Text(row.title)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    CodingUsageValueText(counts: row.counts, isLoading: isLoading)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity)
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
            return .primary
        case .pi:
            return .accentColor
        }
    }
}
