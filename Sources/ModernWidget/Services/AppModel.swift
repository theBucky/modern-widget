import Foundation
import UserNotifications

@MainActor
final class AppModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var reminderMinutes: Int {
        didSet {
            if isPaused {
                pausedRemainingSeconds = min(pausedRemainingSeconds, reminderMinutes * 60)
            }

            defaults.set(reminderMinutes, forKey: Keys.reminderMinutes)
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

    @Published private(set) var notificationPermissionStatus = "checking"
    @Published private(set) var reminderStatusMessage: String?
    @Published private(set) var isReminderStatusError = false

    private enum Keys {
        static let reminderMinutes = "reminderMinutes"
        static let lastWalkAt = "lastWalkAt"
        static let isPaused = "isPaused"
        static let pausedRemainingSeconds = "pausedRemainingSeconds"
    }

    private let defaults: UserDefaults
    private let notificationCenter = UNUserNotificationCenter.current()
    private var loopTask: Task<Void, Never>?
    private var lastReminderAt: Date?
    private var lastPublishedMenuBarTitle: String?

    init(defaults: UserDefaults = .standard) {
        let storedReminderMinutes = max(5, defaults.object(forKey: Keys.reminderMinutes) as? Int ?? 50)

        self.defaults = defaults
        self.reminderMinutes = storedReminderMinutes
        self.lastWalkAt = defaults.object(forKey: Keys.lastWalkAt) as? Date ?? .now
        self.isPaused = defaults.bool(forKey: Keys.isPaused)
        self.pausedRemainingSeconds = defaults.object(forKey: Keys.pausedRemainingSeconds) as? Int
            ?? storedReminderMinutes * 60

        super.init()

        notificationCenter.delegate = self

        refreshNotificationState()
        startLoop()
    }

    deinit {
        loopTask?.cancel()
    }

    var menuBarTitle: String {
        if isPaused {
            return "|| \(countdownLabel)"
        }

        if isOverdue {
            return "Walk"
        }

        return countdownLabel
    }

    var isOverdue: Bool {
        !isPaused && displayedSecondsRemaining == 0
    }

    var countdownLabel: String {
        let totalSeconds = displayedSecondsRemaining
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var breakSummary: String {
        if isPaused {
            return "chair break paused at \(countdownLabel)"
        }

        if isOverdue {
            return "get off chair, move a bit"
        }

        return "off chair in \(countdownLabel)"
    }

    var lastWalkSummary: String {
        "last chair break \(lastWalkAt.formatted(date: .omitted, time: .shortened))"
    }

    var pauseButtonTitle: String {
        isPaused ? "Resume" : "Pause"
    }

    func resetReminder() {
        isPaused = false
        pausedRemainingSeconds = reminderMinutes * 60
        lastWalkAt = .now
        lastReminderAt = nil
        setReminderStatus(nil)
    }

    func togglePause() {
        if isPaused {
            resumeReminder()
            return
        }

        pauseReminder()
    }

    func sendTestReminder() {
        enqueueReminderNotification(body: "get off chair, stretch, walk a minute.")
    }

    private var activeSecondsRemaining: Int {
        let interval = TimeInterval(reminderMinutes * 60)
        let elapsed = Date().timeIntervalSince(lastWalkAt)
        return max(0, Int(ceil(interval - elapsed)))
    }

    private var displayedSecondsRemaining: Int {
        isPaused ? pausedRemainingSeconds : activeSecondsRemaining
    }

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick() async {
        let currentMenuBarTitle = menuBarTitle

        if currentMenuBarTitle != lastPublishedMenuBarTitle {
            lastPublishedMenuBarTitle = currentMenuBarTitle
            objectWillChange.send()
        }

        if isOverdue {
            maybeSendReminder()
        }
    }

    private func maybeSendReminder() {
        let now = Date()
        let reminderCooldown = TimeInterval(reminderMinutes * 60)

        if let lastReminderAt, now.timeIntervalSince(lastReminderAt) < reminderCooldown {
            return
        }

        lastReminderAt = now
        enqueueReminderNotification(body: "get off chair. short walk now.")
    }

    private func refreshNotificationState() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await refreshNotificationSettings()
        }
    }

    private func pauseReminder() {
        pausedRemainingSeconds = activeSecondsRemaining
        isPaused = true
        setReminderStatus("timer paused")
    }

    private func resumeReminder() {
        let interval = reminderMinutes * 60
        let elapsedBeforePause = interval - pausedRemainingSeconds

        isPaused = false
        lastWalkAt = Date().addingTimeInterval(TimeInterval(-elapsedBeforePause))
        setReminderStatus("timer resumed")
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
            try await addNotificationRequest(request)
            setReminderStatus("notification queued")
        } catch {
            applyNotificationError(error)
        }
    }

    private func enqueueReminderNotification(body: String) {
        Task { @MainActor [weak self] in
            await self?.postReminderNotification(body: body)
        }
    }

    private func refreshNotificationSettings() async {
        let authorizationStatus = await notificationAuthorizationStatus()
        notificationPermissionStatus = permissionLabel(for: authorizationStatus)
    }

    private func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: granted)
            }
        }
    }

    private func ensureNotificationAuthorization() async -> Bool {
        let authorizationStatus = await notificationAuthorizationStatus()

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationPermissionStatus = permissionLabel(for: authorizationStatus)
            return true
        case .notDetermined:
            do {
                let granted = try await requestAuthorization()
                await refreshNotificationSettings()

                if !granted {
                    setReminderStatus("notifications blocked in System Settings", isError: true)
                }

                return granted
            } catch {
                applyNotificationError(error)
                return false
            }
        case .denied:
            notificationPermissionStatus = "denied"
            setReminderStatus("notifications blocked in System Settings", isError: true)
            return false
        @unknown default:
            notificationPermissionStatus = "unknown"
            setReminderStatus("unknown notification permission state", isError: true)
            return false
        }
    }

    private func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            notificationCenter.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func permissionLabel(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            "allowed"
        case .provisional:
            "provisional"
        case .ephemeral:
            "ephemeral"
        case .denied:
            "denied"
        case .notDetermined:
            "not asked"
        @unknown default:
            "unknown"
        }
    }

    private func applyNotificationError(_ error: Error) {
        let nsError = error as NSError

        if nsError.domain == UNErrorDomain, nsError.code == 1 {
            notificationPermissionStatus = "denied"
            setReminderStatus("notifications blocked in System Settings", isError: true)
            return
        }

        notificationPermissionStatus = "error"
        setReminderStatus(error.localizedDescription, isError: true)
    }

    private func setReminderStatus(_ message: String?, isError: Bool = false) {
        reminderStatusMessage = message
        isReminderStatusError = message == nil ? false : isError
    }

    private func addNotificationRequest(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            notificationCenter.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume()
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
