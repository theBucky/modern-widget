import Foundation

@MainActor
final class PopupViewModel: ObservableObject {
    @Published private(set) var snapshot: PopupSnapshot

    let walkHistory: WalkHistoryStore

    private let engine: ReminderEngine
    private let refreshLoop = RefreshLoop()
    private var isActive = false

    init(engine: ReminderEngine) {
        self.engine = engine
        self.snapshot = engine.popupSnapshot()
        self.walkHistory = engine.walkHistory

        engine.addObserver(owner: self) { [weak self] in
            guard let self, isActive else {
                return
            }

            refresh()
        }
    }

    var reminderMinuteOptions: [Int] {
        ReminderEngine.reminderMinutePresets
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

    func activate() {
        isActive = true
        refresh()
    }

    func deactivate() {
        isActive = false
        refreshLoop.cancel()
    }

    private func refresh(now: Date = .now) {
        let nextSnapshot = engine.popupSnapshot(at: now)

        if nextSnapshot != snapshot {
            snapshot = nextSnapshot
        }

        refreshLoop.schedule(after: engine.nextRefreshDelay(now: now)) { [weak self] in
            guard let self, isActive else {
                return
            }

            refresh()
        }
    }
}
