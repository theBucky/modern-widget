import Foundation
import UserNotifications

@MainActor
protocol ReminderNotifying {
    func postReminder() async -> ReminderNotificationIssue?
}

@MainActor
final class ReminderNotifier: ReminderNotifying {
    private let notificationCenter: UNUserNotificationCenter
    private let notificationDelegate = NotificationDelegate()

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        notificationCenter.delegate = notificationDelegate
    }

    func postReminder() async -> ReminderNotificationIssue? {
        if let authorizationIssue = await authorizationIssue() {
            return authorizationIssue
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Off-chair break")
        content.body = String(localized: "get off chair. short walk now.")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "off-chair-break-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
            return nil
        } catch {
            return ReminderNotificationIssue(deliveryError: error)
        }
    }

    private func authorizationIssue() async -> ReminderNotificationIssue? {
        let status = await notificationCenter.notificationSettings().authorizationStatus
        guard status == .notDetermined else {
            return ReminderNotificationIssue(authorizationStatus: status)
        }

        do {
            let granted = try await notificationCenter.requestAuthorization(options: [
                .alert, .sound,
            ])
            return granted ? nil : .notificationsBlocked
        } catch {
            return ReminderNotificationIssue(deliveryError: error)
        }
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
