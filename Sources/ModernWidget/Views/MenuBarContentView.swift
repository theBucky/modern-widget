import SwiftUI

struct MenuBarContentView: View {
    @StateObject private var viewModel: PopupViewModel
    @State private var selectedPane = Pane.main

    private let onSizeChange: (CGSize) -> Void

    init(engine: ReminderEngine, onSizeChange: @escaping (CGSize) -> Void) {
        _viewModel = StateObject(wrappedValue: PopupViewModel(engine: engine))
        self.onSizeChange = onSizeChange
    }

    private enum Pane: Hashable {
        case main
        case calendar
    }

    private enum Layout {
        static let mainPaneWidth: CGFloat = 180
        static let calendarPaneWidth: CGFloat = 260
        static let borderPadding: CGFloat = 20
        static let unitSpacing: CGFloat = 20
        static let toolbarIconSize: CGFloat = 22
        static let actionButtonSize: CGFloat = 34
    }

    var body: some View {
        VStack(spacing: Layout.unitSpacing) {
            toolbar
            paneBody
        }
        .padding(Layout.borderPadding)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            onSizeChange(size)
        }
    }

    @ViewBuilder
    private var paneBody: some View {
        switch selectedPane {
        case .main:
            VStack(spacing: Layout.unitSpacing) {
                ReminderStatusView(snapshot: viewModel.snapshot)
                actionsSection
                footerSection
            }
            .frame(width: Layout.mainPaneWidth)
        case .calendar:
            CalendarView(historyStore: viewModel.walkHistory)
                .frame(width: Layout.calendarPaneWidth)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            paneButton(.main, systemImage: "timer")
            paneButton(.calendar, systemImage: "calendar")
            Spacer()
            intervalMenu
        }
    }

    private func paneButton(_ pane: Pane, systemImage: String) -> some View {
        Button {
            selectedPane = pane
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: Layout.toolbarIconSize, height: Layout.toolbarIconSize)
                .foregroundStyle(selectedPane == pane ? Color.accentColor : .secondary)
        }
        .buttonStyle(.borderless)
    }

    private var intervalMenu: some View {
        Menu {
            ForEach(viewModel.reminderMinuteOptions, id: \.self) { minutes in
                Button("\(minutes) min") {
                    viewModel.setReminderMinutes(minutes)
                }
            }
        } label: {
            Text("\(viewModel.snapshot.reminderMinutes) min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var actionsSection: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.togglePause()
            } label: {
                Image(systemName: pauseButtonSymbolName(for: viewModel.snapshot.phase))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: Layout.actionButtonSize, height: Layout.actionButtonSize)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())

            Button {
                viewModel.resetReminder()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: Layout.actionButtonSize, height: Layout.actionButtonSize)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private var footerSection: some View {
        Text("reset \(viewModel.snapshot.lastWalkAt.formatted(date: .omitted, time: .shortened))")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private func pauseButtonSymbolName(for phase: ReminderPhase) -> String {
        switch phase {
        case .paused:
            return "play.fill"
        case .countingDown, .overdue:
            return "pause.fill"
        }
    }
}

private struct ReminderStatusView: View {
    let snapshot: PopupSnapshot

    var body: some View {
        VStack(spacing: 4) {
            Text(statusTitle(for: snapshot))
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(statusTint(for: snapshot))

            Text(statusMessage(for: snapshot.phase))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let reminderStatusMessage = snapshot.reminderStatusMessage {
                Text(reminderStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statusTint(for snapshot: PopupSnapshot) -> Color {
        switch snapshot.phase {
        case .paused:
            return .secondary
        case .overdue:
            return .red
        case .countingDown:
            return .primary
        }
    }

    private func statusTitle(for snapshot: PopupSnapshot) -> String {
        switch snapshot.phase {
        case .overdue:
            return "MOVE"
        case .paused, .countingDown:
            return snapshot.countdownLabel
        }
    }

    private func statusMessage(for phase: ReminderPhase) -> String {
        switch phase {
        case .countingDown:
            return "until next break"
        case .paused:
            return "paused"
        case .overdue:
            return "muscles atrophy, circulation stops, you know..."
        }
    }
}
