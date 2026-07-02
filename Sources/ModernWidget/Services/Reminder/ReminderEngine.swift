import Foundation
import Observation

@MainActor
@Observable
final class ReminderEngine {
    private enum Keys {
        static let state = "reminderState"
        // Pre-Codable scheme, migrated once into `state` then removed.
        static let legacyMinutes = "reminderMinutes"
        static let legacyStartedAt = "reminderStartedAt"
        static let legacyIsPaused = "isPaused"
        static let legacyPausedSeconds = "pausedRemainingSeconds"
    }

    /// Boundary-aligned countdown snapshot driving both the menu bar icon and the
    /// panel; refreshed exactly on whole-second boundaries so the displayed digit
    /// never lags the true remaining time. Carries the latest delivery status too.
    private(set) var currentSnapshot: ReminderSnapshot

    /// Latest notification delivery status. Delivery is not timer state, so it lives
    /// here rather than in `ReminderState`; it reaches the UI folded into snapshots.
    @ObservationIgnored
    private var notificationIssue: ReminderNotificationIssue?

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let notifier: ReminderNotifying
    @ObservationIgnored
    private var snapshotRefreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var reminderTask: Task<Void, Never>?
    @ObservationIgnored
    private var lastReminderAt: Date?
    private var state: ReminderState

    var reminderMinutes: Int {
        get { state.reminderMinutes }
        set { applyReminderMinutes(newValue) }
    }

    func snapshot(at date: Date) -> ReminderSnapshot {
        ReminderSnapshot(state.countdown(at: date), notificationIssue: notificationIssue)
    }

    init(defaults: UserDefaults = .standard, notifier: ReminderNotifying = ReminderNotifier()) {
        let state = Self.loadState(defaults: defaults)
        self.defaults = defaults
        self.notifier = notifier
        self.state = state
        self.notificationIssue = nil
        self.currentSnapshot = ReminderSnapshot(state.countdown(at: .now), notificationIssue: nil)

        syncReminderTaskToState()
        refreshSnapshot()
    }

    deinit {
        snapshotRefreshTask?.cancel()
        reminderTask?.cancel()
    }

    private func applyReminderMinutes(_ minutes: Int) {
        let reminderMinutes = ReminderState.supportedReminderMinutes(for: minutes)
        if reminderMinutes == state.reminderMinutes {
            return
        }

        let now = Date.now
        lastReminderAt = nil
        updateState {
            $0.setReminderMinutes(reminderMinutes)
            $0.restart(at: now)
        }
    }

    func togglePause() {
        let now = Date.now
        updateState {
            $0.togglePause(at: now)
        }
    }

    func completeBreak(at date: Date) {
        lastReminderAt = nil
        updateState {
            $0.restart(at: date)
        }
    }

    private static func loadState(defaults: UserDefaults) -> ReminderState {
        if let data = defaults.data(forKey: Keys.state),
            let decoded = try? JSONDecoder().decode(ReminderState.self, from: data)
        {
            return decoded
        }
        if let migrated = migrateLegacyState(defaults: defaults) {
            return migrated
        }
        return ReminderState(
            reminderMinutes: ReminderState.minutePresets.min()!,
            mode: .running(startedAt: .now)
        )
    }

    private static func migrateLegacyState(defaults: UserDefaults) -> ReminderState? {
        guard defaults.object(forKey: Keys.legacyMinutes) != nil else {
            return nil
        }

        let reminderMinutes = defaults.integer(forKey: Keys.legacyMinutes)
        let mode: ReminderMode =
            defaults.bool(forKey: Keys.legacyIsPaused)
            ? .paused(
                secondsRemaining: defaults.object(forKey: Keys.legacyPausedSeconds) as? Int
                    ?? reminderMinutes * 60)
            : .running(startedAt: defaults.object(forKey: Keys.legacyStartedAt) as? Date ?? .now)

        let state = ReminderState(reminderMinutes: reminderMinutes, mode: mode)
        persist(state, to: defaults)
        for key in [
            Keys.legacyMinutes, Keys.legacyStartedAt, Keys.legacyIsPaused, Keys.legacyPausedSeconds,
        ] {
            defaults.removeObject(forKey: key)
        }
        return state
    }

    private static func persist(_ state: ReminderState, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        defaults.set(data, forKey: Keys.state)
    }

    /// A user timer action supersedes any prior delivery status, so mutating the
    /// state clears the issue in the same beat and refreshes the snapshot once.
    private func updateState(_ update: (inout ReminderState) -> Void) {
        let previousState = state
        let hadIssue = notificationIssue != nil
        update(&state)
        notificationIssue = nil
        guard state != previousState || hadIssue else {
            return
        }

        if state != previousState {
            Self.persist(state, to: defaults)
            syncReminderTaskToState()
        }
        refreshSnapshot()
    }

    private func applyNotificationIssue(_ issue: ReminderNotificationIssue?) {
        guard issue != notificationIssue else {
            return
        }
        notificationIssue = issue
        refreshSnapshot()
    }

    private func refreshSnapshot() {
        let countdown = state.countdown(at: .now)
        let nextSnapshot = ReminderSnapshot(countdown, notificationIssue: notificationIssue)
        if nextSnapshot != currentSnapshot {
            currentSnapshot = nextSnapshot
        }

        scheduleSnapshotRefresh(after: countdown.nextRefreshDelay)
    }

    private func scheduleSnapshotRefresh(after delay: TimeInterval?) {
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = nil

        guard let delay else {
            return
        }

        snapshotRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            self?.refreshSnapshot()
        }
    }

    private func syncReminderTaskToState() {
        reminderTask?.cancel()
        reminderTask = nil

        guard case .running = state.mode else {
            return
        }

        reminderTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let delay = state.nextReminderDelay(lastReminderAt: lastReminderAt, now: .now)
                else { return }

                if delay > 0 {
                    do {
                        try await Task.sleep(for: .seconds(delay))
                    } catch {
                        return
                    }
                }

                await sendReminderIfDue(now: .now)
            }
        }
    }

    private func sendReminderIfDue(now: Date) async {
        guard let delay = state.nextReminderDelay(lastReminderAt: lastReminderAt, now: now),
            delay == 0
        else {
            return
        }

        lastReminderAt = now
        let issue = await notifier.postReminder()
        if Task.isCancelled {
            return
        }

        applyNotificationIssue(issue)
    }
}
