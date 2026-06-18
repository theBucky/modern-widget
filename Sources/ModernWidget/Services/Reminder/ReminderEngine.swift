import Foundation
import Observation

@MainActor
@Observable
final class ReminderEngine {
    private enum Keys {
        static let reminderMinutes = "reminderMinutes"
        static let startedAt = "lastWalkAt"
        static let isPaused = "isPaused"
        static let pausedRemainingSeconds = "pausedRemainingSeconds"
    }

    private(set) var snapshot: ReminderSnapshot

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let notifier: ReminderNotifier
    @ObservationIgnored
    private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored
    private var reminderTask: Task<Void, Never>?
    @ObservationIgnored
    private var lastReminderAt: Date?
    private var state: ReminderState

    var reminderMinutes: Int {
        state.reminderMinutes
    }

    init(defaults: UserDefaults = .standard, notifier: ReminderNotifier = ReminderNotifier()) {
        let state = Self.loadState(defaults: defaults)
        self.defaults = defaults
        self.notifier = notifier
        self.state = state
        self.snapshot = state.snapshot(at: .now)

        syncReminderTaskToState()
        refreshSnapshot()
    }

    deinit {
        snapshotTask?.cancel()
        reminderTask?.cancel()
    }

    func setReminderMinutes(_ minutes: Int) {
        let normalizedMinutes = ReminderState.normalizedReminderMinutes(minutes)
        if normalizedMinutes == state.reminderMinutes {
            return
        }

        let now = Date.now
        lastReminderAt = nil
        updateState {
            $0.reminderMinutes = normalizedMinutes
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
        let storedReminderMinutes = ReminderState.normalizedReminderMinutes(
            defaults.integer(forKey: Keys.reminderMinutes)
        )
        let reminderSeconds = storedReminderMinutes * 60
        let storedPausedSeconds =
            defaults.object(forKey: Keys.pausedRemainingSeconds) as? Int ?? reminderSeconds
        let pausedSeconds = min(max(storedPausedSeconds, 0), reminderSeconds)
        let mode: ReminderMode =
            defaults.bool(forKey: Keys.isPaused)
            ? .paused(secondsRemaining: pausedSeconds)
            : .running

        return ReminderState(
            reminderMinutes: storedReminderMinutes,
            startedAt: defaults.object(forKey: Keys.startedAt) as? Date ?? .now,
            mode: mode,
            notificationIssue: nil
        )
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
        refreshSnapshot()
    }

    private func persistState() {
        defaults.set(state.reminderMinutes, forKey: Keys.reminderMinutes)
        defaults.set(state.startedAt, forKey: Keys.startedAt)

        switch state.mode {
        case .running:
            defaults.set(false, forKey: Keys.isPaused)
            defaults.set(state.reminderSeconds, forKey: Keys.pausedRemainingSeconds)
        case let .paused(secondsRemaining):
            defaults.set(true, forKey: Keys.isPaused)
            defaults.set(secondsRemaining, forKey: Keys.pausedRemainingSeconds)
        }
    }

    private func refreshSnapshot(now: Date = .now) {
        let nextSnapshot = state.snapshot(at: now)
        if nextSnapshot != snapshot {
            snapshot = nextSnapshot
        }

        scheduleSnapshotRefresh(after: state.schedule.countdown(at: now).nextRefreshDelay)
    }

    private func scheduleSnapshotRefresh(after delay: TimeInterval?) {
        snapshotTask?.cancel()
        snapshotTask = nil

        guard let delay else {
            return
        }

        snapshotTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            if Task.isCancelled {
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
