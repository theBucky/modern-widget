import Foundation
import UserNotifications

@MainActor
final class AppModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private enum ReminderDisplayState {
        case countingDown
        case paused
        case overdue
    }

    private static let reminderMinutePresets = [60, 120]

    @Published var reminderMinutes: Int {
        didSet {
            defaults.set(reminderMinutes, forKey: Keys.reminderMinutes)
            resetReminder()
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

        super.init()

        notificationCenter.delegate = self
        startLoop()
    }

    deinit {
        loopTask?.cancel()
    }

    var isOverdue: Bool {
        !isPaused && displayedSecondsRemaining == 0
    }

    var reminderMinuteOptions: [Int] {
        Self.reminderMinutePresets
    }

    var countdownLabel: String {
        let totalSeconds = displayedSecondsRemaining
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var menuBarLabelText: String {
        switch reminderDisplayState {
        case .countingDown, .paused:
            countdownLabel
        case .overdue:
            "Walk"
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
            "Break"
        }
    }

    var statusMessage: String {
        switch reminderDisplayState {
        case .countingDown:
            "until next break"
        case .paused:
            "paused"
        case .overdue:
            "time to stretch"
        }
    }

    func resetReminder() {
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

    private var activeSecondsRemaining: Int {
        let interval = TimeInterval(reminderMinutes * 60)
        let elapsed = Date().timeIntervalSince(lastWalkAt)
        return max(0, Int(ceil(interval - elapsed)))
    }

    private var displayedSecondsRemaining: Int {
        isPaused ? pausedRemainingSeconds : activeSecondsRemaining
    }

    private var reminderDisplayState: ReminderDisplayState {
        if isPaused {
            return .paused
        }

        if isOverdue {
            return .overdue
        }

        return .countingDown
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
        let currentMenuBarTitle = "\(menuBarSymbolName) \(menuBarLabelText)"

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

    private func pauseReminder() {
        pausedRemainingSeconds = activeSecondsRemaining
        isPaused = true
        setReminderStatus(nil)
    }

    private func resumeReminder() {
        let interval = reminderMinutes * 60
        let elapsedBeforePause = interval - pausedRemainingSeconds

        isPaused = false
        lastWalkAt = Date().addingTimeInterval(TimeInterval(-elapsedBeforePause))
        setReminderStatus(nil)
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
            return true
        case .notDetermined:
            do {
                let granted = try await requestAuthorization()
                if !granted {
                    setReminderStatus("notifications blocked in System Settings", isError: true)
                }
                return granted
            } catch {
                applyNotificationError(error)
                return false
            }
        case .denied:
            setReminderStatus("notifications blocked in System Settings", isError: true)
            return false
        @unknown default:
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

    private func applyNotificationError(_ error: Error) {
        let nsError = error as NSError

        if nsError.domain == UNErrorDomain, nsError.code == 1 {
            setReminderStatus("notifications blocked in System Settings", isError: true)
            return
        }

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

    private static func normalizedReminderMinutes(_ minutes: Int) -> Int {
        reminderMinutePresets.min { abs($0 - minutes) < abs($1 - minutes) } ?? reminderMinutePresets[0]
    }
}
