import Foundation
import Testing

@testable import ModernWidget

@Suite("Reminder state")
struct ReminderStateTests {
    @Test("restart always resumes countdown and clears notification issue")
    func restartResumesCountdown() {
        let restartedAt = date(2026, 5, 13, 11)
        var state = ReminderState(
            reminderMinutes: 60,
            startedAt: date(2026, 5, 13, 9),
            mode: .paused(secondsRemaining: 300),
            notificationIssue: .notificationsBlocked
        )

        state.restart(at: restartedAt)
        let snapshot = state.snapshot(at: restartedAt)

        #expect(state.mode == .running)
        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.lastResetAt == restartedAt)
        #expect(snapshot.reminderStatusMessage == nil)
    }

    @Test("resume keeps elapsed progress")
    func resumePreservesElapsedProgress() {
        let resumedAt = date(2026, 5, 13, 12)
        var state = ReminderState(
            reminderMinutes: 60,
            startedAt: date(2026, 5, 13, 9),
            mode: .paused(secondsRemaining: 900),
            notificationIssue: nil
        )

        state.resume(at: resumedAt)

        #expect(state.startedAt == resumedAt.addingTimeInterval(-2700))
        #expect(state.mode == .running)
    }

    @Test("pause freezes visible countdown and clears notification issue")
    func pauseFreezesCountdown() {
        let pausedAt = date(2026, 5, 13, 9, 15)
        var state = ReminderState(
            reminderMinutes: 60,
            startedAt: date(2026, 5, 13, 9),
            mode: .running,
            notificationIssue: .deliveryFailure("network down")
        )

        state.pause(at: pausedAt)
        let snapshot = state.snapshot(at: date(2026, 5, 13, 10))

        #expect(state.mode == .paused(secondsRemaining: 2700))
        #expect(snapshot.phase == .paused)
        #expect(snapshot.secondsRemaining == 2700)
        #expect(snapshot.countdownLabel == "45:00")
        #expect(snapshot.reminderStatusMessage == nil)
    }

    @Test("snapshot reports progress, label, and notification issue")
    func snapshotReportsVisibleState() {
        let state = ReminderState(
            reminderMinutes: 60,
            startedAt: date(2026, 5, 13, 9),
            mode: .running,
            notificationIssue: .notificationsBlocked
        )

        let snapshot = state.snapshot(at: date(2026, 5, 13, 9, 30))

        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.progress == 0.5)
        #expect(snapshot.secondsRemaining == 1800)
        #expect(snapshot.countdownLabel == "30:00")
        #expect(snapshot.reminderStatusMessage == "notifications blocked in System Settings")
    }

    @Test("minute input snaps to supported options")
    func normalizedReminderMinutes() {
        #expect(ReminderState.normalizedReminderMinutes(45) == 60)
        #expect(ReminderState.normalizedReminderMinutes(90) == 60)
        #expect(ReminderState.normalizedReminderMinutes(100) == 120)
        #expect(ReminderState.normalizedReminderMinutes(Int.min) == 60)
        #expect(ReminderState.normalizedReminderMinutes(Int.max) == 120)
    }
}
