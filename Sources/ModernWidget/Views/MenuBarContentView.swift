import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appModel: AppModel

    private enum Layout {
        static let width: CGFloat = 320
        static let contentPadding: CGFloat = 22
        static let sectionSpacing: CGFloat = 12
        static let buttonSpacing: CGFloat = 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            breakSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.contentPadding)
        .frame(width: Layout.width, alignment: .topLeading)
    }

    private var breakSection: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
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

            HStack(spacing: Layout.buttonSpacing) {
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
