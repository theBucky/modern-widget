import Foundation
import Testing
import UserNotifications

@testable import ModernWidget

@Suite("Reminder notification issue")
struct ReminderNotificationIssueTests {
    @Test("issues expose user-visible messages")
    func issuesExposeMessages() {
        #expect(
            message(ReminderNotificationIssue.notificationsBlocked)
                == "notifications blocked in System Settings")
        #expect(
            message(ReminderNotificationIssue.unknownPermissionState)
                == "unknown notification permission state")
        #expect(message(.deliveryFailure("network down")) == "network down")
        #expect(message(.deliveryFailure("disk 100% full")) == "disk 100% full")
    }

    @Test("denied authorization normalizes to blocked")
    func deniedAuthorizationIsBlocked() {
        #expect(ReminderNotificationIssue(authorizationStatus: .denied) == .notificationsBlocked)
    }

    @Test("granted authorization produces no issue")
    func grantedAuthorizationHasNoIssue() {
        #expect(ReminderNotificationIssue(authorizationStatus: .authorized) == nil)
        #expect(ReminderNotificationIssue(authorizationStatus: .provisional) == nil)
        #expect(ReminderNotificationIssue(authorizationStatus: .notDetermined) == nil)
    }

    @Test("ephemeral authorization produces no issue")
    func ephemeralAuthorizationHasNoIssue() {
        let ephemeral = unsafeBitCast(Int(4), to: UNAuthorizationStatus.self)
        #expect(ReminderNotificationIssue(authorizationStatus: ephemeral) == nil)
    }

    @Test("unknown authorization status normalizes to unknown permission state")
    func unknownAuthorizationStatus() {
        let unknown = unsafeBitCast(Int(99), to: UNAuthorizationStatus.self)
        #expect(ReminderNotificationIssue(authorizationStatus: unknown) == .unknownPermissionState)
    }

    @Test("notifications-not-allowed delivery error normalizes to blocked")
    func notificationsNotAllowedErrorIsBlocked() {
        let error = NSError(
            domain: UNErrorDomain,
            code: UNError.Code.notificationsNotAllowed.rawValue
        )
        #expect(ReminderNotificationIssue(deliveryError: error) == .notificationsBlocked)
    }

    @Test("other delivery errors preserve the localized failure message")
    func otherDeliveryErrorPreservesMessage() {
        let error = NSError(
            domain: "ModernWidgetTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "disk full"]
        )
        #expect(ReminderNotificationIssue(deliveryError: error) == .deliveryFailure("disk full"))
    }

    private func message(_ issue: ReminderNotificationIssue) -> String {
        String(localized: issue.message)
    }
}
