import Foundation

@MainActor
final class PopupViewModel: ObservableObject {
    @Published private(set) var snapshot: PopupSnapshot

    let walkHistory: WalkHistoryStore

    private let engine: ReminderEngine

    private var observerID: UUID?
    private var refreshTask: Task<Void, Never>?

    init(engine: ReminderEngine) {
        self.engine = engine
        self.snapshot = engine.popupSnapshot()
        self.walkHistory = engine.walkHistory
    }

    var reminderMinuteOptions: [Int] {
        engine.reminderMinuteOptions
    }

    func start() {
        if observerID == nil {
            observerID = engine.addObserver { [weak self] in
                self?.refresh()
            }
        }

        refresh(rescheduleIfUnchanged: true)
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil

        if let observerID {
            engine.removeObserver(observerID)
            self.observerID = nil
        }
    }

    func setReminderMinutes(_ minutes: Int) {
        engine.setReminderMinutes(minutes)
    }

    func togglePause() {
        engine.togglePause()
    }

    func resetReminder() {
        engine.resetReminder()
    }

    private func refresh(rescheduleIfUnchanged: Bool = false) {
        let nextSnapshot = engine.popupSnapshot()

        if nextSnapshot == snapshot, !rescheduleIfUnchanged {
            return
        }

        snapshot = nextSnapshot
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = nil

        guard let delay = engine.nextRefreshDelay() else {
            return
        }

        refreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            self?.refresh()
        }
    }
}
