import SwiftUI

struct CodingUsageView: View {
    let store: CodingUsageStore

    var body: some View {
        let presentation = store.presentation

        VStack(spacing: PanelLayout.sectionSpacing) {
            CodingUsageTodayTotalSection(summary: presentation.today)
            Divider()
            ForEach(presentation.sections) { section in
                AgentUsageSection(section: section)
            }
        }
        .redacted(reason: presentation.isLoading ? .placeholder : [])
    }
}

private struct AgentUsageSection: View {
    let section: CodingUsagePresentation.AgentSection

    var body: some View {
        VStack(alignment: .leading, spacing: PanelLayout.contentSpacing) {
            HStack(spacing: 6) {
                Image(section.agent.logoResourceName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)

                Text(section.agent.title)
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: PanelLayout.sectionSpacing) {
                CodingUsageTable(periodTotals: section.periodTotals)

                CodingUsageChart(
                    days: section.chartDays,
                    barColor: section.agent.barColor
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
}

private struct CodingUsageTable: View {
    let periodTotals: [CodingUsagePresentation.PeriodTotal]

    var body: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: PanelLayout.contentSpacing,
            verticalSpacing: PanelLayout.tightSpacing
        ) {
            ForEach(periodTotals) { total in
                GridRow {
                    Text(total.period.title)
                        .foregroundStyle(.secondary)
                    CodingUsageValueText(counts: total.counts)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity)
    }
}

extension CodingUsagePeriod {
    fileprivate var title: LocalizedStringResource {
        switch self {
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .last7Days:
            return "Last 7 Days"
        case .last30Days:
            return "Last 30 Days"
        }
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
