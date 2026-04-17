import Foundation

@MainActor
final class PopupViewModel: ObservableObject {
    @Published private(set) var snapshot: PopupSnapshot

    let walkHistory: WalkHistoryStore

    private let engine: ReminderEngine
    private let refreshLoop = RefreshLoop()

    init(engine: ReminderEngine) {
        self.engine = engine
        self.snapshot = engine.popupSnapshot()
        self.walkHistory = engine.walkHistory
    }

    var reminderMinuteOptions: [Int] {
        engine.reminderMinuteOptions
    }

    func start() {
        engine.addObserver(owner: self) { [weak self] in
            self?.refresh()
        }

        refresh(rescheduleIfUnchanged: true)
    }

    func stop() {
        refreshLoop.cancel()
        engine.removeObserver(owner: self)
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

    private func refresh(rescheduleIfUnchanged: Bool = false, now: Date = .now) {
        let nextSnapshot = engine.popupSnapshot(at: now)

        if nextSnapshot == snapshot, !rescheduleIfUnchanged {
            scheduleRefresh(now: now)
            return
        }

        snapshot = nextSnapshot
        scheduleRefresh(now: now)
    }

    private func scheduleRefresh(now: Date) {
        refreshLoop.schedule(after: engine.nextRefreshDelay(now: now)) { [weak self] in
            self?.refresh(now: .now)
        }
    }
}
