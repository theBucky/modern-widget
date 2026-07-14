#if DEBUG
    import SwiftUI

    /// Debug-only wrapper for eyeballing the today-total animation: replay rewinds the
    /// section to a synthetic lower summary for a beat, then releases it so the cost
    /// roll and layout animate back to the real values.
    struct CodingUsageTodayTotalReplayHarness: View {
        let summary: CodingUsageTodaySummary

        @State private var isRewound = false

        var body: some View {
            VStack(alignment: .trailing, spacing: PanelLayout.tightSpacing) {
                replayButton
                CodingUsageTodayTotalSection(
                    summary: isRewound ? Self.replayStartSummary(for: summary) : summary
                )
            }
            .task(id: isRewound) {
                guard isRewound else {
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(120))
                } catch {
                    return
                }

                isRewound = false
            }
        }

        private var replayButton: some View {
            Button {
                isRewound = true
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Replay summary animation")
            .accessibilityLabel("Replay summary animation")
        }

        private static func replayStartSummary(for summary: CodingUsageTodaySummary)
            -> CodingUsageTodaySummary
        {
            var totals = summary.totals
            let targetCostUSD = max(summary.totals.costUSD, 0.15)
            totals.costUSD = max(targetCostUSD * 0.35, 0.01)
            totals.totalTokens = max(summary.totals.totalTokens / 3, 1)

            return CodingUsageTodaySummary(
                date: summary.date,
                totals: totals,
                costTrend: CodingUsageCostTrend(
                    currentCostUSD: totals.costUSD,
                    previousCostUSD: totals.costUSD * 2
                )
            )
        }
    }
#endif
