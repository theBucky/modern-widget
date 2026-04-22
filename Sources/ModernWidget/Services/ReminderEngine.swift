import Foundation

enum ReminderPhase: Equatable {
    case countingDown
    case paused
    case overdue
}

struct MenuBarSnapshot: Equatable {
    let phase: ReminderPhase
    let progress: Double
}

struct PopupSnapshot: Equatable {
    let reminderMinutes: Int
    let phase: ReminderPhase
    let countdownLabel: String
    let reminderStatusMessage: String?
    let lastWalkAt: Date
}

@MainActor
final class ReminderEngine {
    private struct CountdownState: Equatable {
        let phase: ReminderPhase
        let remainingTime: TimeInterval
        let secondsRemaining: Int

        var nextRefreshDelay: TimeInterval? {
            guard phase == .countingDown, remainingTime > 0 else {
                return nil
            }

            let fractional = remainingTime.truncatingRemainder(dividingBy: 1)
            return fractional == 0 ? 1 : fractional
        }
    }

    private enum Keys {
        static let reminderMinutes = "reminderMinutes"
        static let lastWalkAt = "lastWalkAt"
        static let isPaused = "isPaused"
        static let pausedRemainingSeconds = "pausedRemainingSeconds"
    }

    static let reminderMinutePresets = [60, 120]

    let walkHistory: WalkHistoryStore

    private let defaults: UserDefaults
    private let notifier: ReminderNotifier

    private struct ObserverEntry {
        weak var owner: AnyObject?
        let callback: @MainActor () -> Void
    }

    private var observers: [ObjectIdentifier: ObserverEntry] = [:]
    private var reminderTask: Task<Void, Never>?
    private var lastReminderAt: Date?

    private(set) var reminderMinutes: Int {
        didSet {
            defaults.set(reminderMinutes, forKey: Keys.reminderMinutes)
        }
    }

    private(set) var lastWalkAt: Date {
        didSet {
            defaults.set(lastWalkAt, forKey: Keys.lastWalkAt)
        }
    }

    private(set) var isPaused: Bool {
        didSet {
            defaults.set(isPaused, forKey: Keys.isPaused)
        }
    }

    private(set) var pausedRemainingSeconds: Int {
        didSet {
            defaults.set(pausedRemainingSeconds, forKey: Keys.pausedRemainingSeconds)
        }
    }

    private(set) var lastReminderIssue: ReminderNotificationIssue?

    init(defaults: UserDefaults = .standard, notifier: ReminderNotifier = ReminderNotifier()) {
        let storedReminderMinutes = Self.normalizedReminderMinutes(
            defaults.object(forKey: Keys.reminderMinutes) as? Int ?? Self.reminderMinutePresets[0]
        )
        let maxPausedSeconds = storedReminderMinutes * 60
        let storedPausedSeconds =
            defaults.object(forKey: Keys.pausedRemainingSeconds) as? Int ?? maxPausedSeconds

        self.defaults = defaults
        self.notifier = notifier
        self.reminderMinutes = storedReminderMinutes
        self.lastWalkAt = defaults.object(forKey: Keys.lastWalkAt) as? Date ?? .now
        self.isPaused = defaults.bool(forKey: Keys.isPaused)
        self.pausedRemainingSeconds = min(storedPausedSeconds, maxPausedSeconds)
        self.walkHistory = WalkHistoryStore(defaults: defaults)

        syncReminderTaskToState()
    }

    deinit {
        reminderTask?.cancel()
    }

    func addObserver(owner: AnyObject, _ observer: @escaping @MainActor () -> Void) {
        observers[ObjectIdentifier(owner)] = ObserverEntry(owner: owner, callback: observer)
    }

    func removeObserver(owner: AnyObject) {
        observers.removeValue(forKey: ObjectIdentifier(owner))
    }

    func setReminderMinutes(_ minutes: Int) {
        let normalizedMinutes = Self.normalizedReminderMinutes(minutes)
        if normalizedMinutes == reminderMinutes {
            return
        }

        reminderMinutes = normalizedMinutes
        applyReset(recordWalk: false)
    }

    func togglePause() {
        isPaused ? resumeReminder() : pauseReminder()
    }

    func resetReminder(recordWalk: Bool = true) {
        applyReset(recordWalk: recordWalk)
    }

    func menuBarSnapshot(at date: Date = .now) -> MenuBarSnapshot {
        let countdownState = countdownState(at: date)

        return MenuBarSnapshot(
            phase: countdownState.phase,
            progress: Double(countdownState.secondsRemaining) / Double(reminderSeconds)
        )
    }

    func popupSnapshot(at date: Date = .now) -> PopupSnapshot {
        let countdownState = countdownState(at: date)

        return PopupSnapshot(
            reminderMinutes: reminderMinutes,
            phase: countdownState.phase,
            countdownLabel: Self.countdownLabel(for: countdownState.secondsRemaining),
            reminderStatusMessage: Self.statusMessage(for: lastReminderIssue),
            lastWalkAt: lastWalkAt
        )
    }

    func nextRefreshDelay(now: Date = .now) -> TimeInterval? {
        countdownState(at: now).nextRefreshDelay
    }

    private var reminderSeconds: Int {
        reminderMinutes * 60
    }

    private func applyReset(recordWalk: Bool) {
        pausedRemainingSeconds = reminderSeconds
        lastWalkAt = .now
        lastReminderAt = nil
        lastReminderIssue = nil
        syncReminderTaskToState()

        if recordWalk {
            walkHistory.recordWalk()
        }

        notifyObservers()
    }

    private func countdownState(at date: Date) -> CountdownState {
        if isPaused {
            return CountdownState(
                phase: .paused,
                remainingTime: TimeInterval(pausedRemainingSeconds),
                secondsRemaining: pausedRemainingSeconds
            )
        }

        let remainingTime = Double(reminderSeconds) - date.timeIntervalSince(lastWalkAt)
        if remainingTime <= 0 {
            return CountdownState(phase: .overdue, remainingTime: 0, secondsRemaining: 0)
        }

        return CountdownState(
            phase: .countingDown,
            remainingTime: remainingTime,
            secondsRemaining: Int(ceil(remainingTime))
        )
    }

    private func syncReminderTaskToState() {
        if isPaused {
            stopReminderTask()
            return
        }

        startReminderTask()
    }

    private func stopReminderTask() {
        reminderTask?.cancel()
        reminderTask = nil
    }

    private func startReminderTask() {
        stopReminderTask()
        reminderTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = self.nextReminderCheckDelay(now: .now)

                if delay > 0 {
                    do {
                        try await Task.sleep(for: .seconds(delay))
                    } catch {
                        return
                    }
                }

                self.handleReminderCheck(now: .now)
            }
        }
    }

    private func nextReminderCheckDelay(now: Date) -> TimeInterval {
        guard countdownState(at: now).phase == .overdue else {
            let dueAt = lastWalkAt.addingTimeInterval(TimeInterval(reminderSeconds))
            return max(0, dueAt.timeIntervalSince(now))
        }

        guard let lastReminderAt else {
            return 0
        }

        return max(0, Double(reminderSeconds) - now.timeIntervalSince(lastReminderAt))
    }

    private func handleReminderCheck(now: Date) {
        guard shouldSendReminder(now: now) else {
            return
        }

        lastReminderAt = now
        enqueueReminderNotification(body: "get off chair. short walk now.")
    }

    private func shouldSendReminder(now: Date) -> Bool {
        guard countdownState(at: now).phase == .overdue else {
            return false
        }

        guard let lastReminderAt else {
            return true
        }

        return now.timeIntervalSince(lastReminderAt) >= Double(reminderSeconds)
    }

    private func pauseReminder() {
        pausedRemainingSeconds = countdownState(at: .now).secondsRemaining
        isPaused = true
        lastReminderIssue = nil
        syncReminderTaskToState()
        notifyObservers()
    }

    private func resumeReminder() {
        let elapsedBeforePause = reminderSeconds - pausedRemainingSeconds
        isPaused = false
        lastWalkAt = Date().addingTimeInterval(TimeInterval(-elapsedBeforePause))
        lastReminderIssue = nil
        syncReminderTaskToState()
        notifyObservers()
    }

    private func enqueueReminderNotification(body: String) {
        let notifier = notifier

        Task { @MainActor [weak self, notifier] in
            let reminderIssue = await notifier.postReminder(body: body)
            self?.updateReminderStatus(reminderIssue)
        }
    }

    private func updateReminderStatus(_ issue: ReminderNotificationIssue?) {
        if lastReminderIssue == issue {
            return
        }

        lastReminderIssue = issue
        notifyObservers()
    }

    private func notifyObservers() {
        var staleObserverIDs: [ObjectIdentifier] = []
        staleObserverIDs.reserveCapacity(observers.count)

        for (id, entry) in observers {
            guard entry.owner != nil else {
                staleObserverIDs.append(id)
                continue
            }

            entry.callback()
        }

        for observerID in staleObserverIDs {
            observers.removeValue(forKey: observerID)
        }
    }

    private static func normalizedReminderMinutes(_ minutes: Int) -> Int {
        reminderMinutePresets.min { abs($0 - minutes) < abs($1 - minutes) }
            ?? reminderMinutePresets[0]
    }

    nonisolated private static func countdownLabel(for secondsRemaining: Int) -> String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    private static func statusMessage(for issue: ReminderNotificationIssue?) -> String? {
        switch issue {
        case .none:
            return nil
        case .notificationsBlocked:
            return "notifications blocked in System Settings"
        case .unknownPermissionState:
            return "unknown notification permission state"
        case let .deliveryFailure(message):
            return message
        }
    }
}
