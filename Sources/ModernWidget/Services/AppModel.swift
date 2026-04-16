import Foundation
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    private enum ReminderDisplayState: Equatable {
        case countingDown
        case paused
        case overdue
    }

    private static let reminderMinutePresets = [60, 120]

    @Published var reminderMinutes: Int {
        didSet {
            defaults.set(reminderMinutes, forKey: Keys.reminderMinutes)
            resetReminder(recordWalk: false)
        }
    }

    @Published private(set) var lastWalkAt: Date {
        didSet {
            defaults.set(lastWalkAt, forKey: Keys.lastWalkAt)
        }
    }

    @Published private(set) var isPaused: Bool {
        didSet {
            defaults.set(isPaused, forKey: Keys.isPaused)
        }
    }

    @Published private(set) var pausedRemainingSeconds: Int {
        didSet {
            defaults.set(pausedRemainingSeconds, forKey: Keys.pausedRemainingSeconds)
        }
    }

    @Published private(set) var reminderStatusMessage: String?

    let walkHistory: WalkHistoryStore

    private enum Keys {
        static let reminderMinutes = "reminderMinutes"
        static let lastWalkAt = "lastWalkAt"
        static let isPaused = "isPaused"
        static let pausedRemainingSeconds = "pausedRemainingSeconds"
    }

    private let defaults: UserDefaults
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationDelegate = NotificationDelegate()
    private var loopTask: Task<Void, Never>?
    private var lastReminderAt: Date?
    private var lastPublishedDisplayState: ReminderDisplayState?

    init(defaults: UserDefaults = .standard) {
        let storedReminderMinutes = Self.normalizedReminderMinutes(
            defaults.object(forKey: Keys.reminderMinutes) as? Int ?? Self.reminderMinutePresets[0]
        )
        let maxPausedSeconds = storedReminderMinutes * 60
        let storedPausedSeconds = defaults.object(forKey: Keys.pausedRemainingSeconds) as? Int ?? maxPausedSeconds

        self.defaults = defaults
        self.reminderMinutes = storedReminderMinutes
        self.lastWalkAt = defaults.object(forKey: Keys.lastWalkAt) as? Date ?? .now
        self.isPaused = defaults.bool(forKey: Keys.isPaused)
        self.pausedRemainingSeconds = min(storedPausedSeconds, maxPausedSeconds)
        self.walkHistory = WalkHistoryStore(defaults: defaults)

        notificationCenter.delegate = notificationDelegate
        syncLoopToState()
    }

    deinit {
        loopTask?.cancel()
    }

    var isOverdue: Bool {
        !isPaused && displayedSecondsRemaining == 0
    }

    private var reminderSeconds: Int {
        reminderMinutes * 60
    }

    var reminderMinuteOptions: [Int] {
        Self.reminderMinutePresets
    }

    var countdownLabel: String {
        String(format: "%02d:%02d", displayedSecondsRemaining / 60, displayedSecondsRemaining % 60)
    }

    var menuBarLabelText: String {
        switch reminderDisplayState {
        case .countingDown, .paused:
            countdownLabel
        case .overdue:
            "Move"
        }
    }

    var menuBarSymbolName: String {
        switch reminderDisplayState {
        case .countingDown:
            "timer"
        case .paused:
            "pause.fill"
        case .overdue:
            "figure.walk"
        }
    }

    var statusTitle: String {
        switch reminderDisplayState {
        case .countingDown, .paused:
            countdownLabel
        case .overdue:
            "MOVE"
        }
    }

    var statusMessage: String {
        switch reminderDisplayState {
        case .countingDown:
            "until next break"
        case .paused:
            "paused"
        case .overdue:
            "muscles atrophy, circulation stops, you know..."
        }
    }

    func resetReminder(recordWalk: Bool = true) {
        pausedRemainingSeconds = reminderSeconds
        lastWalkAt = .now
        lastReminderAt = nil
        reminderStatusMessage = nil
        syncLoopToState()
        if recordWalk {
            walkHistory.recordWalk()
        }
    }

    func togglePause() {
        isPaused ? resumeReminder() : pauseReminder()
    }

    private var activeSecondsRemaining: Int {
        let elapsed = Date().timeIntervalSince(lastWalkAt)
        return max(0, Int(ceil(Double(reminderSeconds) - elapsed)))
    }

    private var displayedSecondsRemaining: Int {
        isPaused ? pausedRemainingSeconds : activeSecondsRemaining
    }

    private var reminderDisplayState: ReminderDisplayState {
        switch (isPaused, isOverdue) {
        case (true, _): .paused
        case (_, true): .overdue
        default: .countingDown
        }
    }

    private func syncLoopToState() {
        isPaused ? stopLoop() : startLoop()
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func startLoop() {
        stopLoop()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = self.tick()
                try? await Task.sleep(for: delay)
            }
        }
    }

    private func tick() -> Duration {
        let now = Date()
        let state = reminderDisplayState

        if state != lastPublishedDisplayState {
            lastPublishedDisplayState = state
            objectWillChange.send()
        } else if state == .countingDown {
            objectWillChange.send()
        }

        switch state {
        case .countingDown:
            return .seconds(1)
        case .paused:
            return .seconds(60)
        case .overdue:
            maybeSendReminder(now: now)
            return nextOverdueTickDelay(now: now, lastReminderAt: lastReminderAt ?? now)
        }
    }

    private func maybeSendReminder(now: Date) {
        if let lastReminderAt, now.timeIntervalSince(lastReminderAt) < Double(reminderSeconds) {
            return
        }

        lastReminderAt = now
        enqueueReminderNotification(body: "get off chair. short walk now.")
    }

    private func nextOverdueTickDelay(now: Date, lastReminderAt: Date) -> Duration {
        let remaining = Double(reminderSeconds) - now.timeIntervalSince(lastReminderAt)
        return .seconds(max(1, Int(ceil(remaining))))
    }

    private func pauseReminder() {
        pausedRemainingSeconds = activeSecondsRemaining
        isPaused = true
        reminderStatusMessage = nil
        syncLoopToState()
    }

    private func resumeReminder() {
        let elapsedBeforePause = reminderSeconds - pausedRemainingSeconds
        isPaused = false
        lastWalkAt = Date().addingTimeInterval(TimeInterval(-elapsedBeforePause))
        reminderStatusMessage = nil
        syncLoopToState()
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

    private func enqueueReminderNotification(body: String) {
        Task { @MainActor [weak self] in
            await self?.postReminderNotification(body: body)
        }
    }

    private func ensureNotificationAuthorization() async -> Bool {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
                if !granted {
                    reminderStatusMessage = "notifications blocked in System Settings"
                }
                return granted
            } catch {
                applyNotificationError(error)
                return false
            }
        case .denied:
            reminderStatusMessage = "notifications blocked in System Settings"
            return false
        @unknown default:
            reminderStatusMessage = "unknown notification permission state"
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
    }

    private static func normalizedReminderMinutes(_ minutes: Int) -> Int {
        reminderMinutePresets.min { abs($0 - minutes) < abs($1 - minutes) } ?? reminderMinutePresets[0]
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
