import Foundation
import Testing

@testable import ModernWidget

@Suite("Reminder state")
struct ReminderStateTests {
    @Test("restart resumes the countdown from the given instant")
    func restartResumesCountdown() {
        let restartedAt = date(2026, 5, 13, 11)
        var state = ReminderState(
            reminderMinutes: 60,
            mode: .paused(secondsRemaining: 300)
        )

        state.restart(at: restartedAt)
        let countdown = state.countdown(at: restartedAt)

        #expect(state.mode == .running(startedAt: restartedAt))
        #expect(countdown.phase == .countingDown)
    }

    @Test("pause freezes the visible countdown")
    func pauseFreezesCountdown() {
        let pausedAt = date(2026, 5, 13, 9, 15)
        var state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: date(2026, 5, 13, 9))
        )

        state.togglePause(at: pausedAt)
        let countdown = state.countdown(at: date(2026, 5, 13, 10))

        #expect(state.mode == .paused(secondsRemaining: 2700))
        #expect(countdown.phase == .paused)
        #expect(countdown.secondsRemaining == 2700)
    }

    @Test("toggle pause resumes from the frozen value")
    func togglePauseResumesFromFrozenValue() {
        var state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: date(2026, 5, 13, 9))
        )

        state.togglePause(at: date(2026, 5, 13, 9, 10))
        state.togglePause(at: date(2026, 5, 13, 11))
        let countdown = state.countdown(at: date(2026, 5, 13, 11))

        #expect(state.mode == .running(startedAt: date(2026, 5, 13, 10, 50)))
        #expect(countdown.phase == .countingDown)
        #expect(countdown.secondsRemaining == 3000)
    }

    @Test("pausing captures the live countdown value at a sub-second instant")
    func pauseCapturesLiveCountdownValue() {
        let startedAt = date(2026, 5, 13, 9)
        var state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: startedAt)
        )
        // 0.6s into the countdown the live display still rounds 3599.4 up to 3600;
        // pausing must freeze that same value, not the lower true band.
        let pausedAt = startedAt.addingTimeInterval(0.6)
        let liveSeconds = state.countdown(at: pausedAt).secondsRemaining

        state.togglePause(at: pausedAt)

        #expect(liveSeconds == 3600)
        #expect(state.countdown(at: pausedAt).secondsRemaining == liveSeconds)
    }

    @Test("rapid sub-second pause and resume cycles do not drift the countdown")
    func rapidPauseResumeKeepsCountdownStable() {
        let startedAt = date(2026, 5, 13, 9)
        var state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: startedAt)
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

        let countdown = state.countdown(at: clock)
        #expect(countdown.phase == .countingDown)
        #expect(countdown.secondsRemaining == 3600)
    }

    @Test("pausing an overdue timer freezes zero remaining")
    func pausingOverdueTimerFreezesZeroRemaining() {
        var state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: date(2026, 5, 13, 9))
        )

        state.togglePause(at: date(2026, 5, 13, 10, 1))
        let countdown = state.countdown(at: date(2026, 5, 13, 11))

        #expect(state.mode == .paused(secondsRemaining: 0))
        #expect(countdown.phase == .paused)
        #expect(countdown.secondsRemaining == 0)
    }

    @Test("countdown reports progress, phase, and remaining seconds")
    func countdownReportsVisibleState() {
        let state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: date(2026, 5, 13, 9))
        )

        let countdown = state.countdown(at: date(2026, 5, 13, 9, 30))

        #expect(countdown.phase == .countingDown)
        #expect(countdown.progress == 0.5)
        #expect(countdown.secondsRemaining == 1800)
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
            mode: .running(startedAt: date(2026, 5, 13, 9))
        )

        #expect(state.reminderMinutes == 120)

        state.setReminderMinutes(10)
        #expect(state.reminderMinutes == 60)
    }

    @Test("state clamps paused seconds to supported duration")
    func stateClampsPausedSecondsToSupportedDuration() {
        let state = ReminderState(
            reminderMinutes: 45,
            mode: .paused(secondsRemaining: 9_999)
        )

        #expect(state.reminderMinutes == 60)
        #expect(state.mode == .paused(secondsRemaining: 3_600))
        #expect(state.countdown(at: date(2026, 5, 13, 9)).progress == 1)

        var longState = ReminderState(
            reminderMinutes: 120,
            mode: .paused(secondsRemaining: 7_200)
        )

        longState.setReminderMinutes(60)

        #expect(longState.mode == .paused(secondsRemaining: 3_600))
        #expect(longState.countdown(at: date(2026, 5, 13, 9)).progress == 1)
    }

    @Test("running countdown uses ceiling and aligns refreshes to second changes")
    func runningCountdownRefreshDelay() {
        let startedAt = date(2026, 5, 13, 9)
        let state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: startedAt)
        )

        let countdown = state.countdown(at: startedAt.addingTimeInterval(59.25))

        #expect(countdown.phase == .countingDown)
        #expect(countdown.secondsRemaining == 3541)
        #expect(countdown.nextRefreshDelay == 0.75)
    }

    @Test("near whole second countdown waits for the next full second")
    func nearWholeSecondRefreshDelay() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 0)
        let state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: startedAt)
        )

        let countdown = state.countdown(at: startedAt.addingTimeInterval(2400 - 1e-12))

        #expect(countdown.secondsRemaining == 1200)
        #expect(countdown.nextRefreshDelay == 1)
    }

    @Test("last fractional second is still counting down")
    func lastFractionalSecondIsStillCountingDown() {
        let startedAt = date(2026, 5, 13, 9)
        let state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: startedAt)
        )

        let countdown = state.countdown(at: startedAt.addingTimeInterval(3599.2))

        #expect(countdown.phase == .countingDown)
        #expect(countdown.secondsRemaining == 1)
        #expect(abs((countdown.nextRefreshDelay ?? 0) - 0.8) < 0.0001)
    }

    @Test("paused countdown has no refresh clock")
    func pausedCountdownDoesNotRefresh() {
        let state = ReminderState(
            reminderMinutes: 60,
            mode: .paused(secondsRemaining: 1200)
        )

        let countdown = state.countdown(at: date(2026, 5, 13, 10))

        #expect(countdown.phase == .paused)
        #expect(countdown.secondsRemaining == 1200)
        #expect(countdown.nextRefreshDelay == nil)
    }

    @Test("paused timers never become reminder due")
    func pausedStateHasNoReminderDelay() {
        let state = ReminderState(
            reminderMinutes: 60,
            mode: .paused(secondsRemaining: 1200)
        )
        let delay = state.nextReminderDelay(lastReminderAt: nil, now: date(2026, 5, 13, 12))

        #expect(delay == nil)
    }

    @Test("running timers wait until due")
    func runningStateWaitsUntilDue() {
        let startedAt = date(2026, 5, 13, 9)
        let state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: startedAt)
        )

        #expect(
            state.nextReminderDelay(
                lastReminderAt: nil,
                now: startedAt.addingTimeInterval(1200)
            ) == 2400
        )
    }

    @Test("due countdown is overdue and stops refreshing")
    func dueCountdownIsOverdue() {
        let startedAt = date(2026, 5, 13, 9)
        let state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: startedAt)
        )

        let countdown = state.countdown(at: startedAt.addingTimeInterval(3600))

        #expect(countdown.phase == .overdue)
        #expect(countdown.secondsRemaining == 0)
        #expect(countdown.nextRefreshDelay == nil)
    }

    @Test("overdue reminders repeat by interval")
    func overdueReminderCadence() {
        let startedAt = date(2026, 5, 13, 9)
        let firstOverdueCheck = startedAt.addingTimeInterval(3601)
        let firstReminderAt = firstOverdueCheck
        let state = ReminderState(
            reminderMinutes: 60,
            mode: .running(startedAt: startedAt)
        )

        #expect(state.nextReminderDelay(lastReminderAt: nil, now: firstOverdueCheck) == 0)
        #expect(
            state.nextReminderDelay(
                lastReminderAt: firstReminderAt,
                now: firstReminderAt.addingTimeInterval(1800)
            ) == 1800
        )
        #expect(
            state.nextReminderDelay(
                lastReminderAt: firstReminderAt,
                now: firstReminderAt.addingTimeInterval(3600)
            ) == 0
        )
    }
}
