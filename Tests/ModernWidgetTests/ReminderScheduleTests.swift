import Foundation
import Testing

@testable import ModernWidget

@Suite("Reminder schedule")
struct ReminderScheduleTests {
    @Test("running countdown uses ceiling and aligns refreshes to second changes")
    func runningCountdownRefreshDelay() {
        let startedAt = date(2026, 5, 13, 9)
        let schedule = ReminderSchedule(
            reminderSeconds: 3600,
            startedAt: startedAt,
            mode: .running
        )

        let countdown = schedule.countdown(at: startedAt.addingTimeInterval(59.25))

        #expect(countdown.phase == .countingDown)
        #expect(countdown.secondsRemaining == 3541)
        #expect(countdown.nextRefreshDelay == 0.75)
    }

    @Test("near whole second countdown waits for the next full second")
    func nearWholeSecondRefreshDelay() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 0)
        let schedule = ReminderSchedule(
            reminderSeconds: 3600,
            startedAt: startedAt,
            mode: .running
        )

        let countdown = schedule.countdown(at: startedAt.addingTimeInterval(2400 - 1e-12))

        #expect(countdown.secondsRemaining == 1200)
        #expect(countdown.nextRefreshDelay == 1)
    }

    @Test("last fractional second is still counting down")
    func lastFractionalSecondIsStillCountingDown() {
        let startedAt = date(2026, 5, 13, 9)
        let schedule = ReminderSchedule(
            reminderSeconds: 3600,
            startedAt: startedAt,
            mode: .running
        )

        let countdown = schedule.countdown(at: startedAt.addingTimeInterval(3599.2))

        #expect(countdown.phase == .countingDown)
        #expect(countdown.secondsRemaining == 1)
        #expect(abs((countdown.nextRefreshDelay ?? 0) - 0.8) < 0.0001)
    }

    @Test("paused countdown has no refresh clock")
    func pausedCountdownDoesNotRefresh() {
        let schedule = ReminderSchedule(
            reminderSeconds: 3600,
            startedAt: date(2026, 5, 13, 9),
            mode: .paused(secondsRemaining: 1200)
        )

        let countdown = schedule.countdown(at: date(2026, 5, 13, 10))

        #expect(countdown.phase == .paused)
        #expect(countdown.secondsRemaining == 1200)
        #expect(countdown.nextRefreshDelay == nil)
    }

    @Test("paused schedules never become reminder due")
    func pausedScheduleHasNoReminderDelay() {
        let schedule = ReminderSchedule(
            reminderSeconds: 3600,
            startedAt: date(2026, 5, 13, 9),
            mode: .paused(secondsRemaining: 1200)
        )
        let delay = schedule.nextReminderDelay(lastReminderAt: nil, now: date(2026, 5, 13, 12))

        #expect(delay.isInfinite)
    }

    @Test("running schedules wait until due")
    func runningScheduleWaitsUntilDue() {
        let startedAt = date(2026, 5, 13, 9)
        let schedule = ReminderSchedule(
            reminderSeconds: 3600,
            startedAt: startedAt,
            mode: .running
        )

        #expect(
            schedule.nextReminderDelay(
                lastReminderAt: nil,
                now: startedAt.addingTimeInterval(1200)
            ) == 2400
        )
    }

    @Test("due countdown is overdue and stops refreshing")
    func dueCountdownIsOverdue() {
        let startedAt = date(2026, 5, 13, 9)
        let schedule = ReminderSchedule(
            reminderSeconds: 3600,
            startedAt: startedAt,
            mode: .running
        )

        let countdown = schedule.countdown(at: startedAt.addingTimeInterval(3600))

        #expect(countdown.phase == .overdue)
        #expect(countdown.secondsRemaining == 0)
        #expect(countdown.nextRefreshDelay == nil)
    }

    @Test("overdue reminders repeat by interval")
    func overdueReminderCadence() {
        let startedAt = date(2026, 5, 13, 9)
        let firstOverdueCheck = startedAt.addingTimeInterval(3601)
        let firstReminderAt = firstOverdueCheck
        let schedule = ReminderSchedule(
            reminderSeconds: 3600,
            startedAt: startedAt,
            mode: .running
        )

        #expect(schedule.nextReminderDelay(lastReminderAt: nil, now: firstOverdueCheck) == 0)
        #expect(
            schedule.nextReminderDelay(
                lastReminderAt: firstReminderAt,
                now: firstReminderAt.addingTimeInterval(1800)
            ) == 1800
        )
        #expect(
            schedule.nextReminderDelay(
                lastReminderAt: firstReminderAt,
                now: firstReminderAt.addingTimeInterval(3600)
            ) == 0
        )
    }
}
