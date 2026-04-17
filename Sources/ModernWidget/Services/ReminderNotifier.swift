import Foundation
import UserNotifications

enum ReminderNotificationIssue: Equatable {
    case notificationsBlocked
    case unknownPermissionState
    case deliveryFailure(String)
}

@MainActor
final class ReminderNotifier {
    private let notificationCenter: UNUserNotificationCenter
    private let notificationDelegate = NotificationDelegate()

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        notificationCenter.delegate = notificationDelegate
    }

    func postReminder(body: String) async -> ReminderNotificationIssue? {
        if let authorizationIssue = await authorizationIssue() {
            return authorizationIssue
        }

        let content = UNMutableNotificationContent()
        content.title = "Off-chair break"
        content.body = body
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
            return issue(for: error)
        }
    }

    private func authorizationIssue() async -> ReminderNotificationIssue? {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return nil
        case .notDetermined:
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [
                    .alert, .sound, .badge,
                ])
                return granted ? nil : .notificationsBlocked
            } catch {
                return issue(for: error)
            }
        case .denied:
            return .notificationsBlocked
        @unknown default:
            return .unknownPermissionState
        }
    }

    private func issue(for error: Error) -> ReminderNotificationIssue {
        let nsError = error as NSError

        if nsError.domain == UNErrorDomain, nsError.code == 1 {
            return .notificationsBlocked
        }

        return .deliveryFailure(error.localizedDescription)
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
