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
    private(set) var mode: ReminderMode
    var notificationIssue: ReminderNotificationIssue?

    init(
        reminderMinutes: Int,
        startedAt: Date,
        mode: ReminderMode,
        notificationIssue: ReminderNotificationIssue?
    ) {
        self.reminderMinutes = Self.supportedReminderMinutes(for: reminderMinutes)
        self.startedAt = startedAt
        self.mode = Self.normalizedMode(
            mode,
            reminderSeconds: self.reminderMinutes * 60
        )
        self.notificationIssue = notificationIssue
    }

    /// Snaps any requested minutes onto the nearest supported preset, ties to the lower.
    static func supportedReminderMinutes(for minutes: Int) -> Int {
        let presets = minutePresets.sorted()
        for (lower, upper) in zip(presets, presets.dropFirst()) {
            if minutes <= (lower + upper) / 2 {
                return lower
            }
        }
        return presets.last!
    }

    private static func normalizedMode(_ mode: ReminderMode, reminderSeconds: Int) -> ReminderMode {
        guard case let .paused(secondsRemaining) = mode else {
            return mode
        }
        return .paused(secondsRemaining: min(max(secondsRemaining, 0), reminderSeconds))
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
        mode = Self.normalizedMode(mode, reminderSeconds: reminderSeconds)
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
