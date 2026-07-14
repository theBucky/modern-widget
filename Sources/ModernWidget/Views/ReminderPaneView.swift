import SwiftUI

struct ReminderPaneView: View {
    @Environment(ReminderEngine.self) private var engine

    var body: some View {
        let snapshot = engine.currentSnapshot

        VStack(spacing: PanelLayout.paneSpacing) {
            ReminderIntervalMenu()
            ReminderStatusSection(snapshot: snapshot)
            ReminderActionsSection(phase: snapshot.phase)
            DailySupplementToggle()
        }
    }
}

private struct ReminderIntervalMenu: View {
    @Environment(ReminderEngine.self) private var engine

    var body: some View {
        @Bindable var engine = engine

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
        let display = ReminderStatusDisplay(snapshot)

        VStack(spacing: PanelLayout.tightSpacing) {
            Text(display.title)
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint(for: display.emphasis))

            Text(display.message)
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

    private func tint(for emphasis: ReminderStatusDisplay.Emphasis) -> Color {
        switch emphasis {
        case .active:
            return .primary
        case .muted:
            return .secondary
        case .alert:
            return .red
        }
    }
}

private struct ReminderActionsSection: View {
    let phase: ReminderPhase

    @Environment(ReminderEngine.self) private var engine

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
                engine.completeBreak(at: .now)
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
    @Environment(DailySupplementStore.self) private var store

    var body: some View {
        @Bindable var store = store

        Toggle("daily supplement taken", isOn: $store.isTakenToday)
            .toggleStyle(.checkbox)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
