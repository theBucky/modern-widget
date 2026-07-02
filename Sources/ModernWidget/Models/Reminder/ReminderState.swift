import Foundation

private let secondBoundaryEpsilon: TimeInterval = 1e-6

enum ReminderPhase {
    case countingDown
    case paused
    case overdue
}

/// The timer is either running from a start instant or paused holding a frozen
/// remaining value. Each variant carries exactly the data it needs, so a paused
/// timer has no start date to keep consistent and a running one has no stale
/// remaining count.
enum ReminderMode: Equatable, Codable {
    case running(startedAt: Date)
    case paused(secondsRemaining: Int)
}

struct ReminderState: Equatable {
    static let minutePresets = [60, 120]

    private(set) var reminderMinutes: Int
    private(set) var mode: ReminderMode

    init(reminderMinutes: Int, mode: ReminderMode) {
        self.reminderMinutes = Self.supportedReminderMinutes(for: reminderMinutes)
        self.mode = Self.normalizedMode(mode, reminderSeconds: self.reminderMinutes * 60)
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

    mutating func restart(at date: Date) {
        mode = .running(startedAt: date)
    }

    mutating func setReminderMinutes(_ minutes: Int) {
        reminderMinutes = Self.supportedReminderMinutes(for: minutes)
        mode = Self.normalizedMode(mode, reminderSeconds: reminderSeconds)
    }

    mutating func togglePause(at date: Date) {
        switch mode {
        case .running:
            mode = .paused(secondsRemaining: countdown(at: date).secondsRemaining)
        case let .paused(secondsRemaining):
            let elapsedBeforePause = reminderSeconds - secondsRemaining
            mode = .running(startedAt: date.addingTimeInterval(TimeInterval(-elapsedBeforePause)))
        }
    }

    func countdown(at date: Date) -> ReminderCountdown {
        switch mode {
        case let .paused(secondsRemaining):
            return countdown(
                phase: .paused,
                secondsRemaining: secondsRemaining,
                remainingTime: TimeInterval(secondsRemaining)
            )
        case let .running(startedAt):
            let remainingTime = Double(reminderSeconds) - date.timeIntervalSince(startedAt)
            guard remainingTime > 0 else {
                return countdown(phase: .overdue, secondsRemaining: 0, remainingTime: 0)
            }
            return countdown(
                phase: .countingDown,
                secondsRemaining: max(1, Int(ceil(remainingTime - secondBoundaryEpsilon))),
                remainingTime: remainingTime
            )
        }
    }

    /// Delay until the next reminder is due, or `nil` while paused. `lastReminderAt`
    /// paces the repeat cadence once the timer is already overdue.
    func nextReminderDelay(lastReminderAt: Date?, now: Date) -> TimeInterval? {
        guard case let .running(startedAt) = mode else {
            return nil
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

    private func countdown(
        phase: ReminderPhase,
        secondsRemaining: Int,
        remainingTime: TimeInterval
    ) -> ReminderCountdown {
        ReminderCountdown(
            phase: phase,
            secondsRemaining: secondsRemaining,
            progress: Double(secondsRemaining) / Double(reminderSeconds),
            remainingTime: remainingTime
        )
    }
}

/// One instant's reading of the countdown: the visible fields plus the sub-second
/// timing the engine needs to schedule its next refresh.
struct ReminderCountdown {
    let phase: ReminderPhase
    let secondsRemaining: Int
    let progress: Double
    let remainingTime: TimeInterval

    var nextRefreshDelay: TimeInterval? {
        guard case .countingDown = phase, remainingTime > 0 else {
            return nil
        }

        // Refresh on the next whole-second boundary: a full second away when already
        // sitting on one, otherwise the fractional remainder left until it.
        let fractional = remainingTime.truncatingRemainder(dividingBy: 1)
        if remainingTime > secondBoundaryEpsilon && fractional <= secondBoundaryEpsilon {
            return 1
        }
        return fractional
    }
}

/// Observable projection the menu bar icon and panel render. Delivery status is
/// composed in by the engine; the timer model itself knows nothing about it.
struct ReminderSnapshot: Equatable {
    let phase: ReminderPhase
    let secondsRemaining: Int
    let progress: Double
    let notificationIssue: ReminderNotificationIssue?
}

extension ReminderSnapshot {
    init(_ countdown: ReminderCountdown, notificationIssue: ReminderNotificationIssue?) {
        self.init(
            phase: countdown.phase,
            secondsRemaining: countdown.secondsRemaining,
            progress: countdown.progress,
            notificationIssue: notificationIssue
        )
    }
}

extension ReminderState: Codable {
    private enum CodingKeys: String, CodingKey {
        case reminderMinutes
        case mode
    }

    /// Routes decoding through the normalizing initializer; encoding is synthesized.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            reminderMinutes: try container.decode(Int.self, forKey: .reminderMinutes),
            mode: try container.decode(ReminderMode.self, forKey: .mode)
        )
    }
}
