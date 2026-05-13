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

    mutating func pause(at date: Date) {
        mode = .paused(secondsRemaining: schedule.countdown(at: date).secondsRemaining)
        notificationIssue = nil
    }

    mutating func resume(at date: Date) {
        if case let .paused(secondsRemaining) = mode {
            let elapsedBeforePause = reminderSeconds - secondsRemaining
            startedAt = date.addingTimeInterval(TimeInterval(-elapsedBeforePause))
        }
        mode = .running
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
        let firstPreset = minutePresets[0]
        let lastPreset = minutePresets[minutePresets.count - 1]

        if minutes <= firstPreset {
            return firstPreset
        }
        if minutes >= lastPreset {
            return lastPreset
        }

        return minutePresets.min { abs($0 - minutes) < abs($1 - minutes) } ?? firstPreset
    }

    private static func countdownLabel(for secondsRemaining: Int) -> String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    private static func statusMessage(for issue: ReminderNotificationIssue?) -> String? {
        switch issue {
        case .none:
            return nil
        case .notificationsBlocked:
            return "notifications blocked in System Settings"
        case .unknownPermissionState:
            return "unknown notification permission state"
        case let .deliveryFailure(message):
            return message
        }
    }
}
