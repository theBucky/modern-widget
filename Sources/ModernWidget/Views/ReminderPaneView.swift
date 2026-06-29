import SwiftUI

struct ReminderPaneView: View {
    let engine: ReminderEngine
    let walkHistoryStore: WalkHistoryStore
    @Bindable var dailySupplementStore: DailySupplementStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let snapshot = engine.snapshot(at: context.date)

            VStack(spacing: PanelLayout.paneSpacing) {
                intervalMenu
                statusSection(snapshot: snapshot)
                actionsSection(phase: snapshot.phase)
                Toggle("daily supplement taken", isOn: $dailySupplementStore.isTakenToday)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private func statusSection(snapshot: ReminderSnapshot) -> some View {
        let status = statusDisplay(for: snapshot)

        return VStack(spacing: PanelLayout.tightSpacing) {
            Text(status.title)
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(status.tint)

            Text(status.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let message = snapshot.notificationIssue?.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statusDisplay(for snapshot: ReminderSnapshot) -> (
        title: String, message: String, tint: Color
    ) {
        switch snapshot.phase {
        case .countingDown:
            return (countdownLabel(snapshot), "until next break", .primary)
        case .paused:
            return (countdownLabel(snapshot), "paused", .secondary)
        case .overdue:
            return ("MOVE", "muscles atrophy, circulation stops, you know...", .red)
        }
    }

    private func countdownLabel(_ snapshot: ReminderSnapshot) -> String {
        String(format: "%02d:%02d", snapshot.secondsRemaining / 60, snapshot.secondsRemaining % 60)
    }

    private func actionsSection(phase: ReminderPhase) -> some View {
        let pauseTitle = phase == .paused ? "Resume timer" : "Pause timer"
        let pauseIcon = phase == .paused ? "play.fill" : "pause.fill"
        let actionButtonSize: CGFloat = 34

        return HStack(spacing: PanelLayout.contentSpacing) {
            Button {
                engine.togglePause()
            } label: {
                Label(pauseTitle, systemImage: pauseIcon)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: actionButtonSize, height: actionButtonSize)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .help(pauseTitle)

            Button {
                let now = Date.now
                engine.completeBreak(at: now)
                walkHistoryStore.recordWalk(now)
            } label: {
                Label("Complete break", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: actionButtonSize, height: actionButtonSize)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .keyboardShortcut(.defaultAction)
            .help("Complete break")
        }
    }
}
