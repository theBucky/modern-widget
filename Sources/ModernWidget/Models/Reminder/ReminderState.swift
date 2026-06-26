import Foundation

struct ReminderSnapshot: Equatable {
    let phase: ReminderPhase
    let secondsRemaining: Int
    let progress: Double
    let notificationIssue: ReminderNotificationIssue?
}

enum ReminderInterval: Int, CaseIterable {
    case sixtyMinutes = 60
    case twoHours = 120

    var minutes: Int {
        rawValue
    }

    var seconds: Int {
        minutes * 60
    }

    init(minutes: Int) {
        self = minutes <= 90 ? .sixtyMinutes : .twoHours
    }
}

struct ReminderState: Equatable {
    var reminderInterval: ReminderInterval
    var startedAt: Date
    var mode: ReminderMode
    var notificationIssue: ReminderNotificationIssue?

    var reminderSeconds: Int {
        reminderInterval.seconds
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
            secondsRemaining: countdown.secondsRemaining,
            progress: Double(countdown.secondsRemaining) / Double(reminderSeconds),
            notificationIssue: notificationIssue
        )
    }
}
