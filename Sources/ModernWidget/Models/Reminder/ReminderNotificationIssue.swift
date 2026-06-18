enum ReminderNotificationIssue: Equatable {
    case notificationsBlocked
    case unknownPermissionState
    case deliveryFailure(String)
}
