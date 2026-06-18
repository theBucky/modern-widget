import SwiftUI

struct ReminderPaneView: View {
    let engine: ReminderEngine
    let walkHistoryStore: WalkHistoryStore
    let dailySupplementStore: DailySupplementStore

    private enum Layout {
        static let unitSpacing: CGFloat = 20
        static let actionButtonSize: CGFloat = 34
    }

    var body: some View {
        let snapshot = engine.snapshot

        VStack(spacing: Layout.unitSpacing) {
            intervalMenu
            ReminderStatusView(snapshot: snapshot)
            actionsSection(snapshot: snapshot)
            Toggle(
                "took daily supplement today?",
                isOn: Binding(
                    get: { dailySupplementStore.isTaken(on: .now) },
                    set: { dailySupplementStore.setTaken($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
                let now = Date.now
                engine.completeBreak(at: now)
                walkHistoryStore.recordWalk(now)
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
