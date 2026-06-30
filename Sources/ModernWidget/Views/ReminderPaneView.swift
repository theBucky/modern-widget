import SwiftUI

struct ReminderPaneView: View {
    let engine: ReminderEngine
    let walkHistoryStore: WalkHistoryStore
    let dailySupplementStore: DailySupplementStore

    var body: some View {
        let snapshot = engine.currentSnapshot

        VStack(spacing: PanelLayout.paneSpacing) {
            ReminderIntervalMenu(engine: engine)
            ReminderStatusSection(snapshot: snapshot)
            ReminderActionsSection(
                phase: snapshot.phase,
                engine: engine,
                walkHistoryStore: walkHistoryStore
            )
            DailySupplementToggle(store: dailySupplementStore)
        }
    }
}

private struct ReminderIntervalMenu: View {
    @Bindable var engine: ReminderEngine

    var body: some View {
        Picker("Reminder interval", selection: $engine.reminderMinutes) {
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
}

private struct ReminderStatusSection: View {
    let snapshot: ReminderSnapshot

    var body: some View {
        let status = statusDisplay

        VStack(spacing: PanelLayout.tightSpacing) {
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

    private var statusDisplay: (title: String, message: String, tint: Color) {
        switch snapshot.phase {
        case .countingDown:
            return (countdownLabel, "until next break", .primary)
        case .paused:
            return (countdownLabel, "paused", .secondary)
        case .overdue:
            return ("MOVE", "muscles atrophy, circulation stops, you know...", .red)
        }
    }

    private var countdownLabel: String {
        String(format: "%02d:%02d", snapshot.secondsRemaining / 60, snapshot.secondsRemaining % 60)
    }
}

private struct ReminderActionsSection: View {
    let phase: ReminderPhase
    let engine: ReminderEngine
    let walkHistoryStore: WalkHistoryStore

    var body: some View {
        let pauseTitle = phase == .paused ? "Resume timer" : "Pause timer"
        let pauseIcon = phase == .paused ? "play.fill" : "pause.fill"

        HStack(spacing: PanelLayout.contentSpacing) {
            Button {
                engine.togglePause()
            } label: {
                actionLabel(pauseTitle, systemImage: pauseIcon)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .help(pauseTitle)

            Button {
                let now = Date.now
                engine.completeBreak(at: now)
                walkHistoryStore.recordWalk(now)
            } label: {
                actionLabel("Complete break", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .keyboardShortcut(.defaultAction)
            .help("Complete break")
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 34, height: 34)
    }
}

private struct DailySupplementToggle: View {
    @Bindable var store: DailySupplementStore

    var body: some View {
        Toggle("daily supplement taken", isOn: $store.isTakenToday)
            .toggleStyle(.checkbox)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
