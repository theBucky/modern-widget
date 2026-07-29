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

    private func seed(_ defaults: UserDefaults, _ state: ReminderState) throws {
        defaults.set(try JSONEncoder().encode(state), forKey: "reminderState")
    }

    @Test("loads a persisted codable running state as a visible countdown")
    func loadsPersistedCodableState() throws {
        let defaults = makeDefaults("ReminderEngineTests")
        let now = Date.now
        try seed(
            defaults,
            ReminderState(
                reminderMinutes: 120, mode: .running(startedAt: now.addingTimeInterval(-1800)))
        )

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
    func persistsAcrossReloads() throws {
        let defaults = makeDefaults("ReminderEngineTests")
        try seed(
            defaults,
            ReminderState(
                reminderMinutes: 60,
                mode: .running(startedAt: Date.now.addingTimeInterval(-600))
            )
        )

        let first = makeEngine(defaults)
        first.togglePause()

        let reloaded = makeEngine(defaults)
        let snapshot = reloaded.snapshot(at: .now)

        #expect(snapshot.phase == .paused)
        #expect(snapshot.secondsRemaining == 3000)
    }

    @Test("unsupported persisted minutes normalize to a supported preset")
    func loadsUnsupportedMinutesNormalized() {
        let lowDefaults = makeDefaults("ReminderEngineTests")
        lowDefaults.set(
            Data(#"{"reminderMinutes":45,"mode":{"running":{"startedAt":0}}}"#.utf8),
            forKey: "reminderState"
        )
        #expect(makeEngine(lowDefaults).reminderMinutes == 60)

        let highDefaults = makeDefaults("ReminderEngineTests")
        highDefaults.set(
            Data(#"{"reminderMinutes":200,"mode":{"running":{"startedAt":0}}}"#.utf8),
            forKey: "reminderState"
        )
        #expect(makeEngine(highDefaults).reminderMinutes == 120)
    }

    @Test("persisted paused seconds beyond the duration clamp to the full duration")
    func loadsPausedSecondsClamped() {
        let defaults = makeDefaults("ReminderEngineTests")
        defaults.set(
            Data(#"{"reminderMinutes":60,"mode":{"paused":{"secondsRemaining":9999}}}"#.utf8),
            forKey: "reminderState"
        )

        let snapshot = makeEngine(defaults).snapshot(at: .now)

        #expect(snapshot.phase == .paused)
        #expect(snapshot.secondsRemaining == 3600)
        #expect(snapshot.progress == 1)
    }

    @Test("changing to a different preset restarts the countdown")
    func changingToDifferentPresetRestarts() throws {
        let defaults = makeDefaults("ReminderEngineTests")
        try seed(
            defaults,
            ReminderState(
                reminderMinutes: 60,
                mode: .running(startedAt: Date.now.addingTimeInterval(-600))
            )
        )

        let engine = makeEngine(defaults)
        engine.reminderMinutes = 120
        let snapshot = engine.snapshot(at: .now)

        #expect(engine.reminderMinutes == 120)
        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.secondsRemaining == 7200)
    }

    @Test("changing to an equivalent preset leaves the countdown unchanged")
    func changingToEquivalentPresetLeavesStateUnchanged() throws {
        let defaults = makeDefaults("ReminderEngineTests")
        let now = Date.now
        try seed(
            defaults,
            ReminderState(
                reminderMinutes: 60, mode: .running(startedAt: now.addingTimeInterval(-600)))
        )

        let engine = makeEngine(defaults)
        engine.reminderMinutes = 45
        let snapshot = engine.snapshot(at: now)

        #expect(engine.reminderMinutes == 60)
        #expect(snapshot.secondsRemaining == 3000)
    }

    @Test("completing a break restarts the countdown")
    func completingBreakRestartsCountdown() throws {
        let defaults = makeDefaults("ReminderEngineTests")
        try seed(
            defaults,
            ReminderState(
                reminderMinutes: 60,
                mode: .running(startedAt: Date.now.addingTimeInterval(-7200))
            )
        )

        let engine = makeEngine(defaults)
        let now = Date.now
        engine.completeBreak(at: now)
        let snapshot = engine.snapshot(at: now)

        #expect(snapshot.phase == .countingDown)
        #expect(snapshot.secondsRemaining == 3600)
    }

    @Test("changing to a different preset clears a stale notification issue")
    func changingPresetClearsNotificationIssue() async throws {
        let defaults = makeDefaults("ReminderEngineTests")
        try seed(
            defaults,
            ReminderState(
                reminderMinutes: 60,
                mode: .running(startedAt: Date.now.addingTimeInterval(-7200))
            )
        )

        let engine = makeEngine(defaults, issue: .notificationsBlocked)
        await engine.sendReminderIfDue(now: .now)
        #expect(engine.snapshot(at: .now).notificationIssue == .notificationsBlocked)

        engine.reminderMinutes = 120

        #expect(engine.snapshot(at: .now).notificationIssue == nil)
    }
}
