import SwiftUI

struct MenuBarContentView: View {
    @StateObject private var viewModel: PopupViewModel
    @State private var selectedTab = Tab.main

    init(engine: ReminderEngine) {
        _viewModel = StateObject(wrappedValue: PopupViewModel(engine: engine))
    }

    private enum Tab {
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
            case .main:
                mainContent
            case .calendar:
                CalendarView(historyStore: viewModel.walkHistory)
                    .frame(width: Layout.contentWidth)
            }
        }
        .navigationSplitViewColumnWidth(Layout.contentWidth)
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
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
        ReminderStatusView(snapshot: viewModel.snapshot)
    }

    private var intervalSection: some View {
        Picker(
            "",
            selection: Binding(
                get: { viewModel.snapshot.reminderMinutes },
                set: { viewModel.setReminderMinutes($0) }
            )
        ) {
            ForEach(viewModel.reminderMinuteOptions, id: \.self) { minutes in
                Text("\(minutes) min").tag(minutes)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.togglePause()
            } label: {
                Image(systemName: viewModel.snapshot.isPaused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())

            Button {
                viewModel.resetReminder()
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
}

private struct ReminderStatusView: View {
    let snapshot: PopupSnapshot

    var body: some View {
        VStack(spacing: 6) {
            Text(snapshot.statusTitle)
                .font(.system(size: 42, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(statusTint(for: snapshot))

            Text(snapshot.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let reminderStatusMessage = snapshot.reminderStatusMessage {
                Text(reminderStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("reset \(snapshot.lastWalkAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusTint(for snapshot: PopupSnapshot) -> Color {
        switch (snapshot.isPaused, snapshot.isOverdue) {
        case (true, _): .secondary
        case (_, true): .red
        default: .primary
        }
    }
}
