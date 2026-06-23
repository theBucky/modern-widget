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
        #expect(state.startedAt == restartedAt)
        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.reminderStatusMessage == nil)
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

        state.togglePause(at: pausedAt)
        let snapshot = state.snapshot(at: date(2026, 5, 13, 10))

        #expect(state.mode == .paused(secondsRemaining: 2700))
        #expect(snapshot.phase == .paused)
        #expect(snapshot.countdownLabel == "45:00")
        #expect(snapshot.reminderStatusMessage == nil)
    }

    @Test("toggle pause resumes from the frozen value")
    func togglePauseResumesFromFrozenValue() {
        var state = ReminderState(
            reminderMinutes: 60,
            startedAt: date(2026, 5, 13, 9),
            mode: .running,
            notificationIssue: nil
        )

        state.togglePause(at: date(2026, 5, 13, 9, 10))
        state.togglePause(at: date(2026, 5, 13, 11))
        let snapshot = state.snapshot(at: date(2026, 5, 13, 11))

        #expect(state.startedAt == date(2026, 5, 13, 10, 50))
        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.countdownLabel == "50:00")
    }

    @Test("pausing an overdue timer freezes zero remaining")
    func pausingOverdueTimerFreezesZeroRemaining() {
        var state = ReminderState(
            reminderMinutes: 60,
            startedAt: date(2026, 5, 13, 9),
            mode: .running,
            notificationIssue: nil
        )

        state.togglePause(at: date(2026, 5, 13, 10, 1))
        let snapshot = state.snapshot(at: date(2026, 5, 13, 11))

        #expect(state.mode == .paused(secondsRemaining: 0))
        #expect(snapshot.phase == .paused)
        #expect(snapshot.countdownLabel == "00:00")
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
