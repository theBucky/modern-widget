import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appModel: AppModel
    @State private var selectedTab: Tab? = .main

    private enum Tab: Hashable {
        case main
        case calendar
    }

    private enum Layout {
        static let contentWidth: CGFloat = 220
        static let contentPadding: CGFloat = 20
        static let sectionSpacing: CGFloat = 20
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Timer", systemImage: "timer")
                    .tag(Tab.main)
                Label("History", systemImage: "calendar")
                    .tag(Tab.calendar)
            }
            .labelStyle(.iconOnly)
            .navigationSplitViewColumnWidth(50)
        } detail: {
            switch selectedTab {
            case .main, nil:
                mainContent
            case .calendar:
                CalendarView(historyStore: appModel.walkHistory)
                    .frame(width: Layout.contentWidth)
            }
        }
        .navigationSplitViewColumnWidth(Layout.contentWidth)
    }

    private var mainContent: some View {
        VStack(spacing: Layout.sectionSpacing) {
            statusSection
            intervalSection
            actionsSection
        }
        .padding(Layout.contentPadding)
        .frame(width: Layout.contentWidth)
    }

    private var statusSection: some View {
        VStack(spacing: 6) {
            Text(appModel.statusTitle)
                .font(.system(size: 42, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(statusTint)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy(duration: 0.2), value: appModel.statusTitle)

            Text(appModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let reminderStatusMessage = appModel.reminderStatusMessage {
                Text(reminderStatusMessage)
                    .font(.caption)
                    .foregroundStyle(appModel.isReminderStatusError ? .red : .secondary)
            }

            Text("reset \(appModel.lastWalkAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var intervalSection: some View {
        Picker(selection: $appModel.reminderMinutes) {
            ForEach(appModel.reminderMinuteOptions, id: \.self) { minutes in
                Text("\(minutes) min").tag(minutes)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
    }

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                appModel.togglePause()
            } label: {
                Image(systemName: appModel.isPaused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())

            Button {
                appModel.resetReminder()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private var statusTint: Color {
        if appModel.isPaused {
            return .secondary
        }

        if appModel.isOverdue {
            return .red
        }

        return .primary
    }
}
