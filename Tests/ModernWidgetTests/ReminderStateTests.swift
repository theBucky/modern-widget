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
        #expect(snapshot.notificationIssue == nil)
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
        #expect(snapshot.secondsRemaining == 2700)
        #expect(snapshot.notificationIssue == nil)
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
        #expect(snapshot.secondsRemaining == 3000)
    }

    @Test("pausing captures the live countdown value at a sub-second instant")
    func pauseCapturesLiveCountdownValue() {
        let startedAt = date(2026, 5, 13, 9)
        var state = ReminderState(
            reminderMinutes: 60,
            startedAt: startedAt,
            mode: .running,
            notificationIssue: nil
        )
        // 0.6s into the countdown the live display still rounds 3599.4 up to 3600;
        // pausing must freeze that same value, not the lower true band.
        let pausedAt = startedAt.addingTimeInterval(0.6)
        let liveSeconds = state.snapshot(at: pausedAt).secondsRemaining

        state.togglePause(at: pausedAt)

        #expect(liveSeconds == 3600)
        #expect(state.snapshot(at: pausedAt).secondsRemaining == liveSeconds)
    }

    @Test("rapid sub-second pause and resume cycles do not drift the countdown")
    func rapidPauseResumeKeepsCountdownStable() {
        let startedAt = date(2026, 5, 13, 9)
        var state = ReminderState(
            reminderMinutes: 60,
            startedAt: startedAt,
            mode: .running,
            notificationIssue: nil
        )
        // Ten pause/resume toggles spaced 0.05s apart never let a whole second of
        // running elapse, so the ceiling countdown must hold at the full duration.
        var clock = startedAt
        for _ in 0..<10 {
            clock = clock.addingTimeInterval(0.05)
            state.togglePause(at: clock)
            clock = clock.addingTimeInterval(0.05)
            state.togglePause(at: clock)
        }

        #expect(state.mode == .running)
        #expect(state.snapshot(at: clock).secondsRemaining == 3600)
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
        #expect(snapshot.secondsRemaining == 0)
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
        #expect(snapshot.notificationIssue == .notificationsBlocked)
    }

    @Test("minute input snaps to supported options")
    func supportedReminderMinutesSnapInput() {
        #expect(ReminderState.supportedReminderMinutes(for: 45) == 60)
        #expect(ReminderState.supportedReminderMinutes(for: 90) == 60)
        #expect(ReminderState.supportedReminderMinutes(for: 100) == 120)
        #expect(ReminderState.supportedReminderMinutes(for: Int.min) == 60)
        #expect(ReminderState.supportedReminderMinutes(for: Int.max) == 120)
    }

    @Test("state stores only supported reminder minutes")
    func stateStoresOnlySupportedReminderMinutes() {
        var state = ReminderState(
            reminderMinutes: 999,
            startedAt: date(2026, 5, 13, 9),
            mode: .running,
            notificationIssue: nil
        )

        #expect(state.reminderMinutes == 120)

        state.setReminderMinutes(10)
        #expect(state.reminderMinutes == 60)
    }

    @Test("state clamps paused seconds to supported duration")
    func stateClampsPausedSecondsToSupportedDuration() {
        let state = ReminderState(
            reminderMinutes: 45,
            startedAt: date(2026, 5, 13, 9),
            mode: .paused(secondsRemaining: 9_999),
            notificationIssue: nil
        )

        #expect(state.reminderMinutes == 60)
        #expect(state.mode == .paused(secondsRemaining: 3_600))
        #expect(state.snapshot(at: date(2026, 5, 13, 9)).progress == 1)

        var longState = ReminderState(
            reminderMinutes: 120,
            startedAt: date(2026, 5, 13, 9),
            mode: .paused(secondsRemaining: 7_200),
            notificationIssue: nil
        )

        longState.setReminderMinutes(60)

        #expect(longState.mode == .paused(secondsRemaining: 3_600))
        #expect(longState.snapshot(at: date(2026, 5, 13, 9)).progress == 1)
    }
}
