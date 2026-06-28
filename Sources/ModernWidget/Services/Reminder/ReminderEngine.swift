import Foundation
import Observation

@MainActor
@Observable
final class ReminderEngine {
    private enum Keys {
        static let reminderMinutes = "reminderMinutes"
        static let startedAt = "reminderStartedAt"
        static let legacyStartedAt = "lastWalkAt"
        static let isPaused = "isPaused"
        static let pausedRemainingSeconds = "pausedRemainingSeconds"
    }

    private(set) var menuBarSnapshot: ReminderSnapshot

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let notifier: ReminderNotifying
    @ObservationIgnored
    private var menuBarSnapshotTask: Task<Void, Never>?
    @ObservationIgnored
    private var reminderTask: Task<Void, Never>?
    @ObservationIgnored
    private var lastReminderAt: Date?
    private var state: ReminderState

    var reminderMinutes: Int {
        state.reminderMinutes
    }

    func snapshot(at date: Date) -> ReminderSnapshot {
        state.snapshot(at: date)
    }

    init(defaults: UserDefaults = .standard, notifier: ReminderNotifying = ReminderNotifier()) {
        let state = Self.loadState(defaults: defaults)
        self.defaults = defaults
        self.notifier = notifier
        self.state = state
        self.menuBarSnapshot = state.snapshot(at: .now)

        syncReminderTaskToState()
        refreshMenuBarSnapshot()
    }

    deinit {
        menuBarSnapshotTask?.cancel()
        reminderTask?.cancel()
    }

    func setReminderMinutes(_ minutes: Int) {
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
        // Missing paused seconds clamp to the full supported duration inside ReminderState.
        let mode: ReminderMode =
            defaults.bool(forKey: Keys.isPaused)
            ? .paused(
                secondsRemaining: defaults.object(forKey: Keys.pausedRemainingSeconds) as? Int
                    ?? .max)
            : .running

        return ReminderState(
            reminderMinutes: defaults.integer(forKey: Keys.reminderMinutes),
            startedAt: loadStartedAt(defaults: defaults),
            mode: mode,
            notificationIssue: nil
        )
    }

    private static func loadStartedAt(defaults: UserDefaults) -> Date {
        let storedStartedAt = defaults.object(forKey: Keys.startedAt) as? Date
        let legacyStartedAt = defaults.object(forKey: Keys.legacyStartedAt) as? Date
        let startedAt = storedStartedAt ?? legacyStartedAt ?? .now

        if storedStartedAt == nil, legacyStartedAt != nil {
            defaults.set(startedAt, forKey: Keys.startedAt)
        }
        defaults.removeObject(forKey: Keys.legacyStartedAt)
        return startedAt
    }

    private func updateState(_ update: (inout ReminderState) -> Void) {
        let previousState = state
        update(&state)
        if state == previousState {
            return
        }

        persistState()
        if state.schedule != previousState.schedule {
            syncReminderTaskToState()
        }
        refreshMenuBarSnapshot()
    }

    private func persistState() {
        defaults.set(state.reminderMinutes, forKey: Keys.reminderMinutes)
        defaults.set(state.startedAt, forKey: Keys.startedAt)

        switch state.mode {
        case .running:
            defaults.set(false, forKey: Keys.isPaused)
            defaults.removeObject(forKey: Keys.pausedRemainingSeconds)
        case let .paused(secondsRemaining):
            defaults.set(true, forKey: Keys.isPaused)
            defaults.set(secondsRemaining, forKey: Keys.pausedRemainingSeconds)
        }
    }

    private func refreshMenuBarSnapshot() {
        let now = Date.now
        let nextSnapshot = state.snapshot(at: now)
        if nextSnapshot != menuBarSnapshot {
            menuBarSnapshot = nextSnapshot
        }

        scheduleMenuBarSnapshotRefresh(after: state.schedule.countdown(at: now).nextRefreshDelay)
    }

    private func scheduleMenuBarSnapshotRefresh(after delay: TimeInterval?) {
        menuBarSnapshotTask?.cancel()
        menuBarSnapshotTask = nil

        guard let delay else {
            return
        }

        menuBarSnapshotTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            self?.refreshMenuBarSnapshot()
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
                let delay = state.schedule.nextReminderDelay(
                    lastReminderAt: lastReminderAt, now: .now)

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
        guard state.schedule.nextReminderDelay(lastReminderAt: lastReminderAt, now: now) == 0 else {
            return
        }

        lastReminderAt = now
        let issue = await notifier.postReminder()
        if Task.isCancelled {
            return
        }

        updateState {
            $0.notificationIssue = issue
        }
    }
}
