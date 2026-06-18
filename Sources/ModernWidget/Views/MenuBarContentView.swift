import SwiftUI

struct MenuBarContentView: View {
    private let engine: ReminderEngine
    private let usageStore: CodingUsageStore

    @State private var selectedPane = Pane.main

    init(engine: ReminderEngine, usageStore: CodingUsageStore) {
        self.engine = engine
        self.usageStore = usageStore
    }

    private enum Pane {
        case main
        case calendar
        case usage
    }

    private enum Layout {
        static let mainPaneWidth: CGFloat = 180
        static let detailPaneWidth: CGFloat = 280
        static let borderPadding: CGFloat = 20
        static let unitSpacing: CGFloat = 20
        static let toolbarIconSize: CGFloat = 22
    }

    var body: some View {
        VStack(spacing: Layout.unitSpacing) {
            toolbar
            paneBody
                .id(selectedPane)
                .transition(.opacity)
        }
        .frame(width: paneWidth)
        .padding(Layout.borderPadding)
        .animation(.smooth(duration: 0.18), value: selectedPane)
    }

    @ViewBuilder
    private var paneBody: some View {
        switch selectedPane {
        case .main:
            ReminderPaneView(engine: engine)
        case .calendar:
            CalendarView(
                historyStore: engine.walkHistory,
                supplementStore: engine.dailySupplements
            )
        case .usage:
            CodingUsageView(store: usageStore)
        }
    }

    private var paneWidth: CGFloat {
        switch selectedPane {
        case .main:
            return Layout.mainPaneWidth
        case .calendar, .usage:
            return Layout.detailPaneWidth
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            paneButton(.main, systemImage: "timer")
            paneButton(.calendar, systemImage: "calendar")
            paneButton(.usage, systemImage: "chart.line.uptrend.xyaxis")
            Spacer()
            if selectedPane == .main {
                intervalMenu
            }
        }
        .transaction { transaction in
            transaction.animation = nil
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
            ForEach(ReminderState.minutePresets, id: \.self) { minutes in
                Button("\(minutes) min") {
                    engine.setReminderMinutes(minutes)
                }
            }
        } label: {
            Text("\(engine.reminderMinutes) min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct ReminderPaneView: View {
    let engine: ReminderEngine

    private enum Layout {
        static let unitSpacing: CGFloat = 20
        static let actionButtonSize: CGFloat = 34
    }

    var body: some View {
        let snapshot = engine.snapshot

        VStack(spacing: Layout.unitSpacing) {
            ReminderStatusView(snapshot: snapshot)
            actionsSection(snapshot: snapshot)
            Toggle(
                "took daily supplement today?",
                isOn: Binding(
                    get: { engine.dailySupplements.isTaken(on: .now) },
                    set: { engine.dailySupplements.setTaken($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func actionsSection(snapshot: ReminderSnapshot) -> some View {
        HStack(spacing: 10) {
            Button {
                engine.togglePause()
            } label: {
                Image(systemName: snapshot.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: Layout.actionButtonSize, height: Layout.actionButtonSize)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())

            Button {
                engine.completeWalk()
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
}

private struct ReminderStatusView: View {
    let snapshot: ReminderSnapshot

    var body: some View {
        let currentStatus = status

        VStack(spacing: 4) {
            Text(currentStatus.title)
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(currentStatus.tint)

            Text(currentStatus.message)
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

    private var status: (title: String, message: String, tint: Color) {
        switch snapshot.phase {
        case .countingDown:
            return (snapshot.countdownLabel, "until next break", .primary)
        case .paused:
            return (snapshot.countdownLabel, "paused", .secondary)
        case .overdue:
            return ("MOVE", "muscles atrophy, circulation stops, you know...", .red)
        }
    }
}
