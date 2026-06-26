import Foundation

struct ReminderSnapshot: Equatable {
    let phase: ReminderPhase
    let secondsRemaining: Int
    let progress: Double
    let notificationIssue: ReminderNotificationIssue?
}

struct ReminderState: Equatable {
    static let minutePresets = [60, 120]

    private(set) var reminderMinutes: Int
    var startedAt: Date
    var mode: ReminderMode
    var notificationIssue: ReminderNotificationIssue?

    init(
        reminderMinutes: Int,
        startedAt: Date,
        mode: ReminderMode,
        notificationIssue: ReminderNotificationIssue?
    ) {
        self.reminderMinutes = Self.supportedReminderMinutes(for: reminderMinutes)
        self.startedAt = startedAt
        self.mode = mode
        self.notificationIssue = notificationIssue
    }

    nonisolated static func supportedReminderMinutes(for minutes: Int) -> Int {
        minutes <= 90 ? 60 : 120
    }

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

    mutating func setReminderMinutes(_ minutes: Int) {
        reminderMinutes = Self.supportedReminderMinutes(for: minutes)
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
            secondsRemaining: countdown.secondsRemaining,
            progress: Double(countdown.secondsRemaining) / Double(reminderSeconds),
            notificationIssue: notificationIssue
        )
    }
}
