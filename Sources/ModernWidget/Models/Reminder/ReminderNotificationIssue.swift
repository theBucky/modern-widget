import UserNotifications

enum ReminderNotificationIssue: Equatable {
    case notificationsBlocked
    case unknownPermissionState
    case deliveryFailure(String)

    var message: String {
        switch self {
        case .notificationsBlocked:
            return "notifications blocked in System Settings"
        case .unknownPermissionState:
            return "unknown notification permission state"
        case let .deliveryFailure(message):
            return message
        }
    }

    init?(authorizationStatus status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral, .notDetermined:
            return nil
        case .denied:
            self = .notificationsBlocked
        @unknown default:
            self = .unknownPermissionState
        }
    }

    init(deliveryError error: Error) {
        let nsError = error as NSError
        let notificationsNotAllowed =
            nsError.domain == UNErrorDomain
            && UNError.Code(rawValue: nsError.code) == .notificationsNotAllowed
        self =
            notificationsNotAllowed
            ? .notificationsBlocked
            : .deliveryFailure(error.localizedDescription)
    }
}
