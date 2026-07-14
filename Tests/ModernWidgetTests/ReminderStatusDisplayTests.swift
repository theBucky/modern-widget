import Foundation
import Testing

@testable import ModernWidget

@Suite("Reminder status display")
struct ReminderStatusDisplayTests {
    private func snapshot(phase: ReminderPhase, secondsRemaining: Int = 0) -> ReminderSnapshot {
        ReminderSnapshot(
            phase: phase,
            secondsRemaining: secondsRemaining,
            progress: 1,
            notificationIssue: nil
        )
    }

    @Test("counting down shows a padded countdown until the next break")
    func countingDownDisplay() {
        let display = ReminderStatusDisplay(snapshot(phase: .countingDown, secondsRemaining: 90))

        #expect(display.title == "01:30")
        #expect(display.message == "until next break")
        #expect(display.emphasis == .active)
    }

    @Test("a full hour keeps the minute-second pattern")
    func fullHourStaysMinuteSecond() {
        let display = ReminderStatusDisplay(snapshot(phase: .countingDown, secondsRemaining: 3600))

        #expect(display.title == "60:00")
    }

    @Test("paused shows the frozen countdown muted")
    func pausedDisplay() {
        let display = ReminderStatusDisplay(snapshot(phase: .paused, secondsRemaining: 3000))

        #expect(display.title == "50:00")
        #expect(display.message == "paused")
        #expect(display.emphasis == .muted)
    }

    @Test("overdue shows the move call to action")
    func overdueDisplay() {
        let display = ReminderStatusDisplay(snapshot(phase: .overdue))

        #expect(display.title == "MOVE")
        #expect(display.emphasis == .alert)
    }
}
