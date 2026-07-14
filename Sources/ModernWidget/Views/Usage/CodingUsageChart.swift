import Charts
import SwiftUI

struct CodingUsageChart: View {
    let days: [CodingUsageDaySummary]
    let barColor: Color

    @Environment(\.redactionReasons) private var redactionReasons
    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(days, id: \.date) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Cost", barHeightValue(for: day)),
                    width: .ratio(0.7)
                )
                .foregroundStyle(isRedacted ? Color.secondary.opacity(0.18) : barColor)
            }

            if let selectedDay {
                RuleMark(x: .value("Selected Day", selectedDay.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .annotation(
                        position: .top, spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        chartHoverAnnotation(selectedDay)
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXSelection(value: isRedacted ? .constant(nil) : $selectedDate)
        .chartYScale(domain: 0...chartUpperBound)
        .frame(height: 58)
        .frame(maxWidth: .infinity)
    }

    private var isRedacted: Bool {
        redactionReasons.contains(.placeholder)
    }

    private var maxCost: Double {
        days.map(\.totals.costUSD).max() ?? 0
    }

    private var minimumVisibleCost: Double {
        maxCost > 0 ? maxCost * 0.08 : 0.08
    }

    private var chartUpperBound: Double {
        if isRedacted {
            return 1
        }
        return max(maxCost, minimumVisibleCost)
    }

    private func barHeightValue(for day: CodingUsageDaySummary) -> Double {
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

    private func chartHoverAnnotation(_ day: CodingUsageDaySummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
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
