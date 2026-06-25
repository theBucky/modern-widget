import SwiftUI

struct ReminderPaneView: View {
    let engine: ReminderEngine
    let walkHistoryStore: WalkHistoryStore
    @Bindable var dailySupplementStore: DailySupplementStore

    private enum Layout {
        static let unitSpacing: CGFloat = 20
        static let actionButtonSize: CGFloat = 34
    }

    var body: some View {
        let snapshot = engine.snapshot

        VStack(spacing: Layout.unitSpacing) {
            intervalMenu
            ReminderStatusView(snapshot: snapshot)
            actionsSection(phase: snapshot.phase)
            Toggle("daily supplement taken", isOn: $dailySupplementStore.isTakenToday)
                .toggleStyle(.checkbox)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var intervalMenu: some View {
        Picker(
            "Reminder interval",
            selection: Binding(
                get: { engine.reminderMinutes },
                set: { engine.setReminderMinutes($0) }
            )
        ) {
            ForEach(ReminderState.minutePresets, id: \.self) { minutes in
                Text("\(minutes) min").tag(minutes)
            }
        }
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .fixedSize()
        .labelsHidden()
    }

    private func actionsSection(phase: ReminderPhase) -> some View {
        let pauseTitle = phase == .paused ? "Resume timer" : "Pause timer"
        let pauseIcon = phase == .paused ? "play.fill" : "pause.fill"

        return HStack(spacing: 10) {
            Button {
                engine.togglePause()
            } label: {
                Label(pauseTitle, systemImage: pauseIcon)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: Layout.actionButtonSize, height: Layout.actionButtonSize)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .help(pauseTitle)

            Button {
                let now = Date.now
                engine.completeBreak(at: now)
                walkHistoryStore.recordWalk(now)
            } label: {
                Label("Complete break", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: Layout.actionButtonSize, height: Layout.actionButtonSize)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .keyboardShortcut(.defaultAction)
            .help("Complete break")
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
