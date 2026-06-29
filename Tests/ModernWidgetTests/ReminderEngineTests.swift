import Foundation
import Testing

@testable import ModernWidget

@MainActor
@Suite("Reminder engine")
struct ReminderEngineTests {
    private final class StubNotifier: ReminderNotifying {
        let issue: ReminderNotificationIssue?

        init(issue: ReminderNotificationIssue? = nil) {
            self.issue = issue
        }

        func postReminder() async -> ReminderNotificationIssue? {
            issue
        }
    }

    private func makeEngine(
        _ defaults: UserDefaults,
        issue: ReminderNotificationIssue? = nil
    ) -> ReminderEngine {
        ReminderEngine(defaults: defaults, notifier: StubNotifier(issue: issue))
    }

    @Test("loads persisted running minutes and start date as a visible countdown")
    func loadsRunningStateAsVisibleTimer() {
        let defaults = makeDefaults("ReminderEngineTests")
        let now = Date.now
        defaults.set(120, forKey: "reminderMinutes")
        defaults.set(now.addingTimeInterval(-1800), forKey: "reminderStartedAt")
        defaults.set(false, forKey: "isPaused")

        let engine = makeEngine(defaults)
        let snapshot = engine.snapshot(at: now)

        #expect(engine.reminderMinutes == 120)
        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.secondsRemaining == 5400)
        #expect(snapshot.notificationIssue == nil)
    }

    @Test("loads persisted paused state with clamped remaining seconds")
    func loadsPausedStateClamped() {
        let defaults = makeDefaults("ReminderEngineTests")
        defaults.set(60, forKey: "reminderMinutes")
        defaults.set(true, forKey: "isPaused")
        defaults.set(9_999, forKey: "pausedRemainingSeconds")

        let engine = makeEngine(defaults)
        let snapshot = engine.snapshot(at: .now)

        #expect(snapshot.phase == .paused)
        #expect(snapshot.secondsRemaining == 3600)
        #expect(snapshot.progress == 1)
    }

    @Test("paused state without stored seconds defaults to the full duration")
    func loadsPausedStateMissingSecondsDefaultsFull() {
        let defaults = makeDefaults("ReminderEngineTests")
        defaults.set(60, forKey: "reminderMinutes")
        defaults.set(true, forKey: "isPaused")

        let engine = makeEngine(defaults)
        let snapshot = engine.snapshot(at: .now)

        #expect(snapshot.phase == .paused)
        #expect(snapshot.secondsRemaining == 3600)
    }

    @Test("unsupported persisted minutes normalize to a supported preset")
    func loadsUnsupportedMinutesNormalized() {
        let lowDefaults = makeDefaults("ReminderEngineTests")
        lowDefaults.set(45, forKey: "reminderMinutes")
        #expect(makeEngine(lowDefaults).reminderMinutes == 60)

        let highDefaults = makeDefaults("ReminderEngineTests")
        highDefaults.set(200, forKey: "reminderMinutes")
        #expect(makeEngine(highDefaults).reminderMinutes == 120)
    }

    @Test("migrates a legacy start date and stops reading the legacy key")
    func migratesLegacyStartDate() {
        let defaults = makeDefaults("ReminderEngineTests")
        let now = Date.now
        defaults.set(60, forKey: "reminderMinutes")
        defaults.set(now.addingTimeInterval(-600), forKey: "lastWalkAt")

        let engine = makeEngine(defaults)
        let snapshot = engine.snapshot(at: now)

        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.secondsRemaining == 3000)
        #expect(defaults.object(forKey: "reminderStartedAt") != nil)
        #expect(defaults.object(forKey: "lastWalkAt") == nil)
    }

    @Test("changing to a different preset restarts the countdown")
    func changingToDifferentPresetRestarts() {
        let defaults = makeDefaults("ReminderEngineTests")
        defaults.set(60, forKey: "reminderMinutes")
        defaults.set(Date.now.addingTimeInterval(-600), forKey: "reminderStartedAt")

        let engine = makeEngine(defaults)
        engine.setReminderMinutes(120)
        let snapshot = engine.snapshot(at: .now)

        #expect(engine.reminderMinutes == 120)
        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.secondsRemaining == 7200)
    }

    @Test("changing to an equivalent preset leaves the countdown unchanged")
    func changingToEquivalentPresetLeavesStateUnchanged() {
        let defaults = makeDefaults("ReminderEngineTests")
        let now = Date.now
        defaults.set(60, forKey: "reminderMinutes")
        defaults.set(now.addingTimeInterval(-600), forKey: "reminderStartedAt")

        let engine = makeEngine(defaults)
        engine.setReminderMinutes(45)
        let snapshot = engine.snapshot(at: now)

        #expect(engine.reminderMinutes == 60)
        #expect(snapshot.secondsRemaining == 3000)
    }

    @Test("changing to a different preset clears a stale notification issue")
    func changingPresetClearsNotificationIssue() async {
        let defaults = makeDefaults("ReminderEngineTests")
        defaults.set(60, forKey: "reminderMinutes")
        defaults.set(Date.now.addingTimeInterval(-7200), forKey: "reminderStartedAt")

        let engine = makeEngine(defaults, issue: .notificationsBlocked)
        await waitForNotificationIssue(engine, expected: .notificationsBlocked)
        #expect(engine.snapshot(at: .now).notificationIssue == .notificationsBlocked)

        engine.setReminderMinutes(120)

        #expect(engine.snapshot(at: .now).notificationIssue == nil)
    }

    private func waitForNotificationIssue(
        _ engine: ReminderEngine,
        expected: ReminderNotificationIssue
    ) async {
        for _ in 0..<200 {
            if engine.snapshot(at: .now).notificationIssue == expected {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
