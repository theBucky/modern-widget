import Foundation

enum ReminderPhase: Equatable {
    case countingDown
    case paused
    case overdue
}

enum ReminderMode: Equatable {
    case running
    case paused(secondsRemaining: Int)
}

struct ReminderCountdown: Equatable {
    let phase: ReminderPhase
    let remainingTime: TimeInterval
    let secondsRemaining: Int

    var nextRefreshDelay: TimeInterval? {
        guard phase == .countingDown, remainingTime > 0 else {
            return nil
        }

        let fractional = remainingTime.truncatingRemainder(dividingBy: 1)
        return fractional == 0 ? 1 : fractional
    }
}

struct ReminderSchedule: Equatable {
    let reminderSeconds: Int
    let startedAt: Date
    let mode: ReminderMode

    func countdown(at date: Date) -> ReminderCountdown {
        switch mode {
        case let .paused(secondsRemaining):
            return ReminderCountdown(
                phase: .paused,
                remainingTime: TimeInterval(secondsRemaining),
                secondsRemaining: secondsRemaining
            )
        case .running:
            let remainingTime = Double(reminderSeconds) - date.timeIntervalSince(startedAt)
            if remainingTime <= 0 {
                return ReminderCountdown(phase: .overdue, remainingTime: 0, secondsRemaining: 0)
            }

            return ReminderCountdown(
                phase: .countingDown,
                remainingTime: remainingTime,
                secondsRemaining: Int(ceil(remainingTime))
            )
        }
    }

    func nextReminderDelay(lastReminderAt: Date?, now: Date) -> TimeInterval {
        if case .paused = mode {
            return .infinity
        }

        guard countdown(at: now).phase == .overdue else {
            let dueAt = startedAt.addingTimeInterval(TimeInterval(reminderSeconds))
            return max(0, dueAt.timeIntervalSince(now))
        }

        guard let lastReminderAt else {
            return 0
        }

        return max(0, Double(reminderSeconds) - now.timeIntervalSince(lastReminderAt))
    }
}
