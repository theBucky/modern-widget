import Foundation

/// Display projection of a reminder snapshot: the title, message, and emphasis the
/// status section renders. Emphasis is semantic so the model stays free of SwiftUI.
struct ReminderStatusDisplay: Equatable {
    enum Emphasis {
        case active
        case muted
        case alert
    }

    let title: String
    let message: LocalizedStringResource
    let emphasis: Emphasis

    init(_ snapshot: ReminderSnapshot) {
        switch snapshot.phase {
        case .countingDown:
            title = Self.countdownLabel(secondsRemaining: snapshot.secondsRemaining)
            message = "until next break"
            emphasis = .active
        case .paused:
            title = Self.countdownLabel(secondsRemaining: snapshot.secondsRemaining)
            message = "paused"
            emphasis = .muted
        case .overdue:
            title = String(localized: "MOVE")
            message = "muscles atrophy, circulation stops, you know..."
            emphasis = .alert
        }
    }

    private static func countdownLabel(secondsRemaining: Int) -> String {
        Duration.seconds(secondsRemaining)
            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    }
}
