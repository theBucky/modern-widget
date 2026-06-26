import Foundation
import Testing

@testable import ModernWidget

@Suite("Reminder state")
struct ReminderStateTests {
    @Test("restart always resumes countdown and clears notification issue")
    func restartResumesCountdown() {
        let restartedAt = date(2026, 5, 13, 11)
        var state = ReminderState(
            reminderInterval: .sixtyMinutes,
            startedAt: date(2026, 5, 13, 9),
            mode: .paused(secondsRemaining: 300),
            notificationIssue: .notificationsBlocked
        )

        state.restart(at: restartedAt)
        let snapshot = state.snapshot(at: restartedAt)

        #expect(state.mode == .running)
        #expect(state.startedAt == restartedAt)
        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.notificationIssue == nil)
    }

    @Test("pause freezes visible countdown and clears notification issue")
    func pauseFreezesCountdown() {
        let pausedAt = date(2026, 5, 13, 9, 15)
        var state = ReminderState(
            reminderInterval: .sixtyMinutes,
            startedAt: date(2026, 5, 13, 9),
            mode: .running,
            notificationIssue: .deliveryFailure("network down")
        )

        state.togglePause(at: pausedAt)
        let snapshot = state.snapshot(at: date(2026, 5, 13, 10))

        #expect(state.mode == .paused(secondsRemaining: 2700))
        #expect(snapshot.phase == .paused)
        #expect(snapshot.secondsRemaining == 2700)
        #expect(snapshot.notificationIssue == nil)
    }

    @Test("toggle pause resumes from the frozen value")
    func togglePauseResumesFromFrozenValue() {
        var state = ReminderState(
            reminderInterval: .sixtyMinutes,
            startedAt: date(2026, 5, 13, 9),
            mode: .running,
            notificationIssue: nil
        )

        state.togglePause(at: date(2026, 5, 13, 9, 10))
        state.togglePause(at: date(2026, 5, 13, 11))
        let snapshot = state.snapshot(at: date(2026, 5, 13, 11))

        #expect(state.startedAt == date(2026, 5, 13, 10, 50))
        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.secondsRemaining == 3000)
    }

    @Test("pausing an overdue timer freezes zero remaining")
    func pausingOverdueTimerFreezesZeroRemaining() {
        var state = ReminderState(
            reminderInterval: .sixtyMinutes,
            startedAt: date(2026, 5, 13, 9),
            mode: .running,
            notificationIssue: nil
        )

        state.togglePause(at: date(2026, 5, 13, 10, 1))
        let snapshot = state.snapshot(at: date(2026, 5, 13, 11))

        #expect(state.mode == .paused(secondsRemaining: 0))
        #expect(snapshot.phase == .paused)
        #expect(snapshot.secondsRemaining == 0)
    }

    @Test("snapshot reports progress, label, and notification issue")
    func snapshotReportsVisibleState() {
        let state = ReminderState(
            reminderInterval: .sixtyMinutes,
            startedAt: date(2026, 5, 13, 9),
            mode: .running,
            notificationIssue: .notificationsBlocked
        )

        let snapshot = state.snapshot(at: date(2026, 5, 13, 9, 30))

        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.progress == 0.5)
        #expect(snapshot.secondsRemaining == 1800)
        #expect(snapshot.notificationIssue == .notificationsBlocked)
    }

    @Test("minute input snaps to supported options")
    func reminderIntervalSnapsMinuteInput() {
        #expect(ReminderInterval(minutes: 45) == .sixtyMinutes)
        #expect(ReminderInterval(minutes: 90) == .sixtyMinutes)
        #expect(ReminderInterval(minutes: 100) == .twoHours)
        #expect(ReminderInterval(minutes: Int.min) == .sixtyMinutes)
        #expect(ReminderInterval(minutes: Int.max) == .twoHours)
    }
}
