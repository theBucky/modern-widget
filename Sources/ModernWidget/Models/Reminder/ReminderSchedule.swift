import Foundation

private let secondBoundaryEpsilon: TimeInterval = 1e-6

enum ReminderPhase {
    case countingDown
    case paused
    case overdue
}

enum ReminderMode: Equatable {
    case running
    case paused(secondsRemaining: Int)
}

struct ReminderCountdown {
    let phase: ReminderPhase
    let remainingTime: TimeInterval
    let secondsRemaining: Int

    var nextRefreshDelay: TimeInterval? {
        guard case .countingDown = phase, remainingTime > 0 else {
            return nil
        }

        let fractional = remainingTime.truncatingRemainder(dividingBy: 1)
        return remainingTime > secondBoundaryEpsilon && fractional <= secondBoundaryEpsilon
            ? 1
            : fractional
    }
}

struct ReminderSchedule: Equatable {
    let reminderSeconds: Int
    let startedAt: Date
    let mode: ReminderMode

    func countdown(at date: Date) -> ReminderCountdown {
        if case let .paused(secondsRemaining) = mode {
            return ReminderCountdown(
                phase: .paused,
                remainingTime: TimeInterval(secondsRemaining),
                secondsRemaining: secondsRemaining
            )
        }

        let remainingTime = Double(reminderSeconds) - date.timeIntervalSince(startedAt)
        guard remainingTime > 0 else {
            return ReminderCountdown(phase: .overdue, remainingTime: 0, secondsRemaining: 0)
        }

        return ReminderCountdown(
            phase: .countingDown,
            remainingTime: remainingTime,
            secondsRemaining: Int(ceil(remainingTime))
        )
    }

    func nextReminderDelay(lastReminderAt: Date?, now: Date) -> TimeInterval {
        if case .paused = mode {
            return .infinity
        }

        let secondsUntilDue =
            startedAt
            .addingTimeInterval(TimeInterval(reminderSeconds))
            .timeIntervalSince(now)
        guard secondsUntilDue <= 0 else {
            return secondsUntilDue
        }

        guard let lastReminderAt else {
            return 0
        }

        return max(0, Double(reminderSeconds) - now.timeIntervalSince(lastReminderAt))
    }
}
