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

    @Test("loads a persisted codable running state as a visible countdown")
    func loadsPersistedCodableState() throws {
        let defaults = makeDefaults("ReminderEngineTests")
        let now = Date.now
        let state = ReminderState(
            reminderMinutes: 120,
            mode: .running(startedAt: now.addingTimeInterval(-1800))
        )
        defaults.set(try JSONEncoder().encode(state), forKey: "reminderState")

        let engine = makeEngine(defaults)
        let snapshot = engine.snapshot(at: now)

        #expect(engine.reminderMinutes == 120)
        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.secondsRemaining == 5400)
        #expect(snapshot.notificationIssue == nil)
    }

    @Test("falls back to a fresh default when the persisted state is unreadable")
    func fallsBackOnUnreadableState() {
        let defaults = makeDefaults("ReminderEngineTests")
        defaults.set(Data("not json".utf8), forKey: "reminderState")

        let engine = makeEngine(defaults)
        let snapshot = engine.snapshot(at: .now)

        #expect(engine.reminderMinutes == 60)
        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.secondsRemaining == 3600)
    }

    @Test("persists state changes across engine reloads")
    func persistsAcrossReloads() {
        let defaults = makeDefaults("ReminderEngineTests")
        defaults.set(60, forKey: "reminderMinutes")
        defaults.set(Date.now.addingTimeInterval(-600), forKey: "reminderStartedAt")

        let first = makeEngine(defaults)
        first.togglePause()

        let reloaded = makeEngine(defaults)
        let snapshot = reloaded.snapshot(at: .now)

        #expect(snapshot.phase == .paused)
        #expect(snapshot.secondsRemaining == 3000)
    }

    @Test("migrates the legacy defaults keys into one codable state")
    func migratesLegacyKeys() {
        let defaults = makeDefaults("ReminderEngineTests")
        let now = Date.now
        defaults.set(60, forKey: "reminderMinutes")
        defaults.set(now.addingTimeInterval(-600), forKey: "reminderStartedAt")
        defaults.set(false, forKey: "isPaused")

        let engine = makeEngine(defaults)
        let snapshot = engine.snapshot(at: now)

        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.secondsRemaining == 3000)
        #expect(defaults.data(forKey: "reminderState") != nil)
        #expect(defaults.object(forKey: "reminderMinutes") == nil)
        #expect(defaults.object(forKey: "reminderStartedAt") == nil)
        #expect(defaults.object(forKey: "isPaused") == nil)
    }

    @Test("migrates a legacy paused state with clamped remaining seconds")
    func migratesLegacyPausedStateClamped() {
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

    @Test("legacy paused state without stored seconds defaults to the full duration")
    func migratesLegacyPausedStateMissingSecondsDefaultsFull() {
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

    @Test("changing to a different preset restarts the countdown")
    func changingToDifferentPresetRestarts() {
        let defaults = makeDefaults("ReminderEngineTests")
        defaults.set(60, forKey: "reminderMinutes")
        defaults.set(Date.now.addingTimeInterval(-600), forKey: "reminderStartedAt")

        let engine = makeEngine(defaults)
        engine.reminderMinutes = 120
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
        engine.reminderMinutes = 45
        let snapshot = engine.snapshot(at: now)

        #expect(engine.reminderMinutes == 60)
        #expect(snapshot.secondsRemaining == 3000)
    }

    @Test("completing a break fires the break-completed hook with the completion date")
    func completingBreakFiresHook() {
        let defaults = makeDefaults("ReminderEngineTests")
        let engine = makeEngine(defaults)
        var recorded: [Date] = []
        engine.onBreakCompleted = { recorded.append($0) }

        let now = Date.now
        engine.completeBreak(at: now)

        #expect(recorded == [now])
    }

    @Test("changing to a different preset clears a stale notification issue")
    func changingPresetClearsNotificationIssue() async {
        let defaults = makeDefaults("ReminderEngineTests")
        defaults.set(60, forKey: "reminderMinutes")
        defaults.set(Date.now.addingTimeInterval(-7200), forKey: "reminderStartedAt")

        let engine = makeEngine(defaults, issue: .notificationsBlocked)
        await waitForNotificationIssue(engine, expected: .notificationsBlocked)
        #expect(engine.snapshot(at: .now).notificationIssue == .notificationsBlocked)

        engine.reminderMinutes = 120

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
