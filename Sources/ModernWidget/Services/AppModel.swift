import AppKit
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

    @Published var quotaURLString: String {
        didSet {
            defaults.set(quotaURLString, forKey: Keys.quotaURLString)

            if normalizedQuotaURL(from: quotaURLString) != normalizedQuotaURL(from: oldValue) {
                resetQuotaState()
                cancelQuotaFetch()
            }
        }
    }

    @Published var quotaRefreshMinutes: Int {
        didSet {
            defaults.set(quotaRefreshMinutes, forKey: Keys.quotaRefreshMinutes)
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

    @Published private(set) var quotaSnapshot: QuotaSnapshot?
    @Published private(set) var quotaError: String?
    @Published private(set) var isFetchingQuota = false
    @Published private(set) var notificationPermissionStatus = "checking"
    @Published private(set) var reminderStatusMessage: String?
    @Published private(set) var isReminderStatusError = false

    private enum Keys {
        static let reminderMinutes = "reminderMinutes"
        static let quotaURLString = "quotaURLString"
        static let quotaRefreshMinutes = "quotaRefreshMinutes"
        static let lastWalkAt = "lastWalkAt"
        static let isPaused = "isPaused"
        static let pausedRemainingSeconds = "pausedRemainingSeconds"
    }

    private let defaults: UserDefaults
    private let quotaService = QuotaService()
    private let notificationCenter = UNUserNotificationCenter.current()
    private var loopTask: Task<Void, Never>?
    private var quotaFetchTask: Task<Void, Never>?
    private var quotaFetchTaskID: UUID?
    private var lastQuotaFetchAt: Date?
    private var lastReminderAt: Date?
    private var lastPublishedMenuBarTitle: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.reminderMinutes = max(5, defaults.object(forKey: Keys.reminderMinutes) as? Int ?? 50)
        self.quotaURLString = defaults.string(forKey: Keys.quotaURLString) ?? ""
        self.quotaRefreshMinutes = max(1, defaults.object(forKey: Keys.quotaRefreshMinutes) as? Int ?? 15)
        self.lastWalkAt = defaults.object(forKey: Keys.lastWalkAt) as? Date ?? .now
        self.isPaused = defaults.bool(forKey: Keys.isPaused)
        self.pausedRemainingSeconds = defaults.object(forKey: Keys.pausedRemainingSeconds) as? Int
            ?? max(5, defaults.object(forKey: Keys.reminderMinutes) as? Int ?? 50) * 60

        super.init()

        notificationCenter.delegate = self

        refreshNotificationState()
        startLoop()
    }

    deinit {
        loopTask?.cancel()
        quotaFetchTask?.cancel()
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
            return "paused at \(countdownLabel)"
        }

        if isOverdue {
            return "time to get up and move"
        }

        return "next reminder in \(countdownLabel)"
    }

    var lastWalkSummary: String {
        "last reset \(lastWalkAt.formatted(date: .omitted, time: .shortened))"
    }

    var pauseButtonTitle: String {
        isPaused ? "Resume" : "Pause"
    }

    var quotaSummary: String {
        if isFetchingQuota {
            return "fetching quota..."
        }

        if let quotaSnapshot {
            return "updated \(quotaSnapshot.fetchedAt.formatted(date: .omitted, time: .shortened))"
        }

        if quotaError != nil {
            return "last fetch failed"
        }

        return "remote JSON not configured"
    }

    var hasValidQuotaURL: Bool {
        normalizedQuotaURL != nil
    }

    func markWalkCompleted() {
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
        enqueueReminderNotification(body: "stretch, walk, shake brain loose.")
    }

    func openQuotaURL() {
        guard let url = normalizedQuotaURL else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshQuotaNow() {
        queueQuotaRefresh(force: true)
    }

    private var normalizedQuotaURL: URL? {
        normalizedQuotaURL(from: quotaURLString)
    }

    private func normalizedQuotaURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            !trimmed.isEmpty,
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            let host = url.host,
            !host.isEmpty
        else {
            return nil
        }

        guard scheme == "https" else {
            return nil
        }

        return url
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

        if shouldAutoRefreshQuota {
            queueQuotaRefresh()
        }
    }

    private var shouldAutoRefreshQuota: Bool {
        guard normalizedQuotaURL != nil, !isFetchingQuota else { return false }
        guard let lastQuotaFetchAt else { return true }

        return Date().timeIntervalSince(lastQuotaFetchAt) >= TimeInterval(quotaRefreshMinutes * 60)
    }

    private func maybeSendReminder() {
        let now = Date()
        let reminderCooldown = TimeInterval(reminderMinutes * 60)

        if let lastReminderAt, now.timeIntervalSince(lastReminderAt) < reminderCooldown {
            return
        }

        lastReminderAt = now
        enqueueReminderNotification(body: "time for a short walk.")
    }

    private func refreshNotificationState() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await refreshNotificationSettings()
        }
    }

    private func queueQuotaRefresh(force: Bool = false) {
        guard force || normalizedQuotaURL != nil else {
            resetQuotaState()
            cancelQuotaFetch()
            return
        }

        guard quotaFetchTask == nil else { return }

        let taskID = UUID()
        quotaFetchTaskID = taskID
        quotaFetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if quotaFetchTaskID == taskID {
                    quotaFetchTask = nil
                    quotaFetchTaskID = nil
                }
            }

            await fetchQuota()
        }
    }

    private func fetchQuota() async {
        guard let url = normalizedQuotaURL else {
            resetQuotaState()
            return
        }

        isFetchingQuota = true
        defer { isFetchingQuota = false }

        do {
            let snapshot = try await quotaService.fetch(from: url)

            guard !Task.isCancelled, normalizedQuotaURL == url else { return }

            quotaSnapshot = snapshot
            quotaError = nil
            lastQuotaFetchAt = .now
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, normalizedQuotaURL == url else { return }

            quotaError = error.localizedDescription
            lastQuotaFetchAt = .now
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
        content.title = "Walk break"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "walk-break-\(UUID().uuidString)",
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

    private func resetQuotaState() {
        quotaSnapshot = nil
        quotaError = nil
        lastQuotaFetchAt = nil
    }

    private func cancelQuotaFetch() {
        quotaFetchTask?.cancel()
        quotaFetchTask = nil
        quotaFetchTaskID = nil
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
