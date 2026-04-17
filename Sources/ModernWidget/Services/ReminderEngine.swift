import Foundation
import UserNotifications

struct MenuBarSnapshot: Equatable {
    let text: String
    let symbolName: String
}

struct PopupSnapshot: Equatable {
    let reminderMinutes: Int
    let statusTitle: String
    let statusMessage: String
    let reminderStatusMessage: String?
    let lastWalkAt: Date
    let isPaused: Bool
    let isOverdue: Bool
}

@MainActor
final class ReminderEngine {
    private enum ReminderDisplayState: Equatable {
        case countingDown
        case paused
        case overdue
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
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationDelegate = NotificationDelegate()

    private var observers: [UUID: @MainActor () -> Void] = [:]
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

    init(defaults: UserDefaults = .standard) {
        let storedReminderMinutes = Self.normalizedReminderMinutes(
            defaults.object(forKey: Keys.reminderMinutes) as? Int ?? Self.reminderMinutePresets[0]
        )
        let maxPausedSeconds = storedReminderMinutes * 60
        let storedPausedSeconds =
            defaults.object(forKey: Keys.pausedRemainingSeconds) as? Int ?? maxPausedSeconds

        self.defaults = defaults
        self.reminderMinutes = storedReminderMinutes
        self.lastWalkAt = defaults.object(forKey: Keys.lastWalkAt) as? Date ?? .now
        self.isPaused = defaults.bool(forKey: Keys.isPaused)
        self.pausedRemainingSeconds = min(storedPausedSeconds, maxPausedSeconds)
        self.walkHistory = WalkHistoryStore(defaults: defaults)

        notificationCenter.delegate = notificationDelegate
        syncReminderTaskToState()
    }

    deinit {
        reminderTask?.cancel()
    }

    var reminderMinuteOptions: [Int] {
        Self.reminderMinutePresets
    }

    func addObserver(_ observer: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
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
        let countdownLabel = Self.countdownLabel(for: displayedSecondsRemaining(at: date))

        switch reminderDisplayState(at: date) {
        case .paused:
            return MenuBarSnapshot(text: countdownLabel, symbolName: "pause.fill")
        case .overdue:
            return MenuBarSnapshot(text: "Move", symbolName: "figure.walk")
        case .countingDown:
            return MenuBarSnapshot(text: countdownLabel, symbolName: "timer")
        }
    }

    func popupSnapshot(at date: Date = .now) -> PopupSnapshot {
        let secondsRemaining = displayedSecondsRemaining(at: date)
        let countdownLabel = Self.countdownLabel(for: secondsRemaining)

        switch reminderDisplayState(at: date) {
        case .paused:
            return PopupSnapshot(
                reminderMinutes: reminderMinutes,
                statusTitle: countdownLabel,
                statusMessage: "paused",
                reminderStatusMessage: reminderStatusMessage,
                lastWalkAt: lastWalkAt,
                isPaused: true,
                isOverdue: false
            )
        case .overdue:
            return PopupSnapshot(
                reminderMinutes: reminderMinutes,
                statusTitle: "MOVE",
                statusMessage: "muscles atrophy, circulation stops, you know...",
                reminderStatusMessage: reminderStatusMessage,
                lastWalkAt: lastWalkAt,
                isPaused: false,
                isOverdue: true
            )
        case .countingDown:
            return PopupSnapshot(
                reminderMinutes: reminderMinutes,
                statusTitle: countdownLabel,
                statusMessage: "until next break",
                reminderStatusMessage: reminderStatusMessage,
                lastWalkAt: lastWalkAt,
                isPaused: false,
                isOverdue: false
            )
        }
    }

    func nextRefreshDelay(now: Date = .now) -> TimeInterval? {
        if reminderDisplayState(at: now) != .countingDown {
            return nil
        }

        let remaining = Double(reminderSeconds) - now.timeIntervalSince(lastWalkAt)
        if remaining <= 0 {
            return nil
        }

        let fractional = remaining.truncatingRemainder(dividingBy: 1)
        return fractional == 0 ? 1 : fractional
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

    private func displayedSecondsRemaining(at date: Date) -> Int {
        if isPaused {
            return pausedRemainingSeconds
        }

        let elapsed = date.timeIntervalSince(lastWalkAt)
        return max(0, Int(ceil(Double(reminderSeconds) - elapsed)))
    }

    private func reminderDisplayState(at date: Date) -> ReminderDisplayState {
        switch (isPaused, displayedSecondsRemaining(at: date) == 0) {
        case (true, _):
            .paused
        case (_, true):
            .overdue
        default:
            .countingDown
        }
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
        if let lastReminderAt, reminderDisplayState(at: now) == .overdue {
            return max(0, Double(reminderSeconds) - now.timeIntervalSince(lastReminderAt))
        }

        let dueAt = lastWalkAt.addingTimeInterval(TimeInterval(reminderSeconds))
        return max(0, dueAt.timeIntervalSince(now))
    }

    private func handleReminderCheck(now: Date) {
        if reminderDisplayState(at: now) != .overdue {
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
        pausedRemainingSeconds = displayedSecondsRemaining(at: .now)
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
        Task { @MainActor [weak self] in
            await self?.postReminderNotification(body: body)
        }
    }

    private func postReminderNotification(body: String) async {
        guard await ensureNotificationAuthorization() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Off-chair break"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "off-chair-break-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            applyNotificationError(error)
        }
    }

    private func ensureNotificationAuthorization() async -> Bool {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [
                    .alert, .sound, .badge,
                ])

                if !granted {
                    reminderStatusMessage = "notifications blocked in System Settings"
                    notifyObservers()
                }

                return granted
            } catch {
                applyNotificationError(error)
                return false
            }
        case .denied:
            reminderStatusMessage = "notifications blocked in System Settings"
            notifyObservers()
            return false
        @unknown default:
            reminderStatusMessage = "unknown notification permission state"
            notifyObservers()
            return false
        }
    }

    private func applyNotificationError(_ error: Error) {
        let nsError = error as NSError

        if nsError.domain == UNErrorDomain, nsError.code == 1 {
            reminderStatusMessage = "notifications blocked in System Settings"
        } else {
            reminderStatusMessage = error.localizedDescription
        }

        notifyObservers()
    }

    private func notifyObservers() {
        for observer in observers.values {
            observer()
        }
    }

    private static func normalizedReminderMinutes(_ minutes: Int) -> Int {
        reminderMinutePresets.min { abs($0 - minutes) < abs($1 - minutes) }
            ?? reminderMinutePresets[0]
    }

    private static func countdownLabel(for secondsRemaining: Int) -> String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
