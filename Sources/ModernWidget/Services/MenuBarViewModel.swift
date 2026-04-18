import Foundation

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var snapshot: MenuBarSnapshot

    private let engine: ReminderEngine
    private let refreshLoop = RefreshLoop()

    init(engine: ReminderEngine) {
        self.engine = engine
        snapshot = engine.menuBarSnapshot()
        engine.addObserver(owner: self) { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    private func refresh(now: Date = .now) {
        let nextSnapshot = engine.menuBarSnapshot(at: now)

        if nextSnapshot != snapshot {
            snapshot = nextSnapshot
        }

        scheduleRefresh(now: now)
    }

    private func scheduleRefresh(now: Date) {
        refreshLoop.schedule(after: engine.nextRefreshDelay(now: now)) { [weak self] in
            self?.refresh(now: .now)
        }
    }
}
