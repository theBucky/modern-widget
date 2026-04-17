import Foundation

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var snapshot: MenuBarSnapshot

    private let engine: ReminderEngine

    private var observerID: UUID?
    private var refreshTask: Task<Void, Never>?

    init(engine: ReminderEngine) {
        self.engine = engine
        self.snapshot = engine.menuBarSnapshot()
        observerID = engine.addObserver { [weak self] in
            self?.refresh()
        }
        refresh(rescheduleIfUnchanged: true)
    }

    private func refresh(rescheduleIfUnchanged: Bool = false) {
        let nextSnapshot = engine.menuBarSnapshot()

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
