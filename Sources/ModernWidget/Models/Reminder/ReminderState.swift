import Foundation

struct ReminderSnapshot: Equatable {
    let phase: ReminderPhase
    let progress: Double
    let secondsRemaining: Int
    let countdownLabel: String
    let reminderStatusMessage: String?
    let lastResetAt: Date
}

struct ReminderState: Equatable {
    static let minutePresets = [60, 120]

    var reminderMinutes: Int
    var startedAt: Date
    var mode: ReminderMode
    var notificationIssue: ReminderNotificationIssue?

    var reminderSeconds: Int {
        reminderMinutes * 60
    }

    var schedule: ReminderSchedule {
        ReminderSchedule(
            reminderSeconds: reminderSeconds,
            startedAt: startedAt,
            mode: mode
        )
    }

    mutating func restart(at date: Date) {
        startedAt = date
        mode = .running
        notificationIssue = nil
    }

    mutating func togglePause(at date: Date) {
        switch mode {
        case .running:
            mode = .paused(secondsRemaining: schedule.countdown(at: date).secondsRemaining)
        case let .paused(secondsRemaining):
            let elapsedBeforePause = reminderSeconds - secondsRemaining
            startedAt = date.addingTimeInterval(TimeInterval(-elapsedBeforePause))
            mode = .running
        }
        notificationIssue = nil
    }

    func snapshot(at date: Date) -> ReminderSnapshot {
        let countdown = schedule.countdown(at: date)

        return ReminderSnapshot(
            phase: countdown.phase,
            progress: Double(countdown.secondsRemaining) / Double(reminderSeconds),
            secondsRemaining: countdown.secondsRemaining,
            countdownLabel: Self.countdownLabel(for: countdown.secondsRemaining),
            reminderStatusMessage: Self.statusMessage(for: notificationIssue),
            lastResetAt: startedAt
        )
    }

    static func normalizedReminderMinutes(_ minutes: Int) -> Int {
        minutes <= 90 ? 60 : 120
    }

    private static func countdownLabel(for secondsRemaining: Int) -> String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    private static func statusMessage(for issue: ReminderNotificationIssue?) -> String? {
        guard let issue else {
            return nil
        }

        switch issue {
        case .notificationsBlocked:
            return "notifications blocked in System Settings"
        case .unknownPermissionState:
            return "unknown notification permission state"
        case let .deliveryFailure(message):
            return message
        }
    }
}
