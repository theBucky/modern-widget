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
