import Charts
import SwiftUI

struct CodingUsageChart: View {
    let days: [CodingUsageDaySummary]
    let barColor: Color

    @Environment(\.redactionReasons) private var redactionReasons
    @State private var selectedDate: Date?

    var body: some View {
        let maxCost = days.lazy.map(\.totals.costUSD).max() ?? 0
        let minimumVisibleCost = maxCost > 0 ? maxCost * 0.08 : 0.08
        let chartUpperBound = isRedacted ? 1 : max(maxCost, minimumVisibleCost)

        Chart {
            ForEach(days, id: \.date) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value(
                        "Cost",
                        barHeightValue(for: day, minimumVisibleCost: minimumVisibleCost)
                    ),
                    width: .ratio(0.7)
                )
                .foregroundStyle(isRedacted ? Color.secondary.opacity(0.18) : barColor)
                .accessibilityLabel(
                    Text(day.date, format: .dateTime.month(.wide).day().year())
                )
                .accessibilityValue(
                    day.totals.totalTokens.formatted(.codingUsageTokens)
                        + ", "
                        + day.totals.costUSD.formatted(.codingUsageCost)
                )
            }

            if let selectedDay {
                RuleMark(x: .value("Selected Day", selectedDay.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .annotation(
                        position: .top, spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        CodingUsageChartAnnotation(day: selectedDay)
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXSelection(value: isRedacted ? .constant(nil) : $selectedDate)
        .chartYScale(domain: 0...chartUpperBound)
        .accessibilityHidden(isRedacted)
        .frame(height: 58)
        .frame(maxWidth: .infinity)
    }

    private var isRedacted: Bool {
        redactionReasons.contains(.placeholder)
    }

    private func barHeightValue(
        for day: CodingUsageDaySummary,
        minimumVisibleCost: Double
    ) -> Double {
        if isRedacted {
            return 1
        }
        guard day.totals.hasCost else {
            return 0
        }
        return max(day.totals.costUSD, minimumVisibleCost)
    }

    private var selectedDay: CodingUsageDaySummary? {
        guard !isRedacted, let selectedDate else {
            return nil
        }
        return days.first { LocalDay.calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }
}

private struct CodingUsageChartAnnotation: View {
    let day: CodingUsageDaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(day.date, format: .dateTime.month(.abbreviated).day())
                .foregroundStyle(.primary)
            CodingUsageValueText(totals: day.totals)
        }
        .font(.caption2.monospacedDigit())
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 4))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }
}
