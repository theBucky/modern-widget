import SwiftUI

struct CalendarView: View {
    @ObservedObject var historyStore: WalkHistoryStore

    var body: some View {
        let grouped = historyStore.walksByDay()

        if grouped.isEmpty {
            emptyState
        } else {
            listView(grouped)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.walk.circle")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No walks yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func listView(_ grouped: [(day: Date, count: Int)]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(grouped, id: \.day) { entry in
                    row(entry)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func row(_ entry: (day: Date, count: Int)) -> some View {
        HStack {
            Text(entry.day, format: .dateTime.month(.abbreviated).day())
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Text("\(entry.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            Image(systemName: "figure.walk")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
