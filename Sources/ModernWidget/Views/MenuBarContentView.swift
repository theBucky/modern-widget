import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                breakSection
                Divider()
                quotaSection
            }
            .padding(16)
        }
        .frame(width: 360, height: 420)
    }

    private var breakSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Break reminder")
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
                Button("Just walk") {
                    appModel.markWalkCompleted()
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
        }
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quota")
                .font(.headline)

            Text(appModel.quotaSummary)
                .foregroundStyle(.secondary)

            TextField("https://example.com/quota.json", text: $appModel.quotaURLString)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Refresh \(appModel.quotaRefreshMinutes) min")
                Spacer()
                Stepper("", value: $appModel.quotaRefreshMinutes, in: 1 ... 120)
                    .labelsHidden()
            }

            HStack(spacing: 10) {
                Button("Refresh now") {
                    appModel.refreshQuotaNow()
                }
                .disabled(!appModel.hasValidQuotaURL)

                Button("Open URL") {
                    appModel.openQuotaURL()
                }
                .disabled(!appModel.hasValidQuotaURL)
            }

            if let quotaError = appModel.quotaError {
                Text(quotaError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let quotaSnapshot = appModel.quotaSnapshot {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(quotaSnapshot.pairs) { pair in
                        LabeledContent(pair.key) {
                            Text(pair.value)
                                .monospacedDigit()
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }
                }
            } else {
                Text("point this at any JSON endpoint, keys flatten into quick rows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
