import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            breakSection
        }
        .padding(16)
        .frame(width: 360, height: 240)
    }

    private var breakSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Off-chair reminder")
                .font(.headline)

            Text(appModel.breakSummary)
                .foregroundStyle(appModel.isOverdue ? .red : .secondary)

            Text(appModel.lastWalkSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Every \(appModel.reminderMinutes) min")
                Spacer()
                Stepper("", value: $appModel.reminderMinutes, in: 5 ... 180, step: 5)
                    .labelsHidden()
            }

            HStack(spacing: 10) {
                Button("Reset timer") {
                    appModel.resetReminder()
                }
                .keyboardShortcut(.defaultAction)

                Button(appModel.pauseButtonTitle) {
                    appModel.togglePause()
                }

                Button("Test ping") {
                    appModel.sendTestReminder()
                }
            }

            Text("notifications: \(appModel.notificationPermissionStatus)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let reminderStatusMessage = appModel.reminderStatusMessage {
                Text(reminderStatusMessage)
                    .font(.caption)
                    .foregroundStyle(appModel.isReminderStatusError ? .red : .secondary)
            }

            Text("break resets when you get up, move, then come back.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
