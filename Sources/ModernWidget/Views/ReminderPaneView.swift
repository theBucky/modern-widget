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
            status.title
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

    private var statusDisplay: ReminderStatusDisplay {
        switch snapshot.phase {
        case .countingDown:
            return ReminderStatusDisplay(
                title: Text(countdownLabel),
                message: "until next break",
                tint: .primary
            )
        case .paused:
            return ReminderStatusDisplay(
                title: Text(countdownLabel),
                message: "paused",
                tint: .secondary
            )
        case .overdue:
            return ReminderStatusDisplay(
                title: Text("MOVE"),
                message: "muscles atrophy, circulation stops, you know...",
                tint: .red
            )
        }
    }

    private var countdownLabel: String {
        Duration.seconds(snapshot.secondsRemaining)
            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    }
}

private struct ReminderStatusDisplay {
    let title: Text
    let message: LocalizedStringResource
    let tint: Color
}

private struct ReminderActionsSection: View {
    let phase: ReminderPhase
    let engine: ReminderEngine
    let walkHistoryStore: WalkHistoryStore

    var body: some View {
        let pauseTitle: LocalizedStringKey = phase == .paused ? "Resume timer" : "Pause timer"
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

    private func actionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
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
