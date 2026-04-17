import Foundation

enum ReminderPhase: Equatable {
    case countingDown
    case paused
    case overdue
}

struct MenuBarSnapshot: Equatable {
    let text: String
    let symbolName: String
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

        var menuBarText: String {
            switch phase {
            case .overdue:
                return "Move"
            case .paused, .countingDown:
                return countdownLabel
            }
        }

        var menuBarSymbolName: String {
            switch phase {
            case .paused:
                return "pause.fill"
            case .overdue:
                return "figure.walk"
            case .countingDown:
                return "timer"
            }
        }

        var countdownLabel: String {
            ReminderEngine.countdownLabel(for: secondsRemaining)
        }

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

    private(set) var reminderStatusMessage: String?

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

    var reminderMinuteOptions: [Int] {
        Self.reminderMinutePresets
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
            text: countdownState.menuBarText,
            symbolName: countdownState.menuBarSymbolName
        )
    }

    func popupSnapshot(at date: Date = .now) -> PopupSnapshot {
        let countdownState = countdownState(at: date)

        return PopupSnapshot(
            reminderMinutes: reminderMinutes,
            phase: countdownState.phase,
            countdownLabel: countdownState.countdownLabel,
            reminderStatusMessage: reminderStatusMessage,
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
        reminderStatusMessage = nil
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
        isPaused ? stopReminderTask() : startReminderTask()
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
        if let lastReminderAt, countdownState(at: now).phase == .overdue {
            return max(0, Double(reminderSeconds) - now.timeIntervalSince(lastReminderAt))
        }

        let dueAt = lastWalkAt.addingTimeInterval(TimeInterval(reminderSeconds))
        return max(0, dueAt.timeIntervalSince(now))
    }

    private func handleReminderCheck(now: Date) {
        if countdownState(at: now).phase != .overdue {
            return
        }

        maybeSendReminder(now: now)
    }

    private func maybeSendReminder(now: Date) {
        if let lastReminderAt, now.timeIntervalSince(lastReminderAt) < Double(reminderSeconds) {
            return
        }

        lastReminderAt = now
        enqueueReminderNotification(body: "get off chair. short walk now.")
    }

    private func pauseReminder() {
        pausedRemainingSeconds = countdownState(at: .now).secondsRemaining
        isPaused = true
        reminderStatusMessage = nil
        syncReminderTaskToState()
        notifyObservers()
    }

    private func resumeReminder() {
        let elapsedBeforePause = reminderSeconds - pausedRemainingSeconds
        isPaused = false
        lastWalkAt = Date().addingTimeInterval(TimeInterval(-elapsedBeforePause))
        reminderStatusMessage = nil
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
        let message = reminderStatusMessage(for: issue)

        if reminderStatusMessage == message {
            return
        }

        reminderStatusMessage = message
        notifyObservers()
    }

    private func notifyObservers() {
        var staleObserverIDs: [ObjectIdentifier] = []

        for (id, entry) in observers {
            guard entry.owner != nil else {
                staleObserverIDs.append(id)
                continue
            }

            entry.callback()
        }

        for id in staleObserverIDs {
            observers.removeValue(forKey: id)
        }
    }

    private static func normalizedReminderMinutes(_ minutes: Int) -> Int {
        reminderMinutePresets.min { abs($0 - minutes) < abs($1 - minutes) }
            ?? reminderMinutePresets[0]
    }

    nonisolated private static func countdownLabel(for secondsRemaining: Int) -> String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    private func reminderStatusMessage(for issue: ReminderNotificationIssue?) -> String? {
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
