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
                CodingUsageAgentSection(
                    summary: summary,
                    reportDate: reportDate,
                    isLoading: isLoading
                )
            }
        }
    }

    private var isLoading: Bool {
        store.report.generatedAt == nil
    }

    private var reportDate: Date {
        store.report.generatedAt ?? .now
    }
}
