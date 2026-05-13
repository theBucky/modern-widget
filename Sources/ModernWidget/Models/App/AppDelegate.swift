import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine: ReminderEngine
    private let menuBarController: MenuBarController

    override init() {
        let engine = ReminderEngine()
        self.engine = engine
        self.menuBarController = MenuBarController(engine: engine)
        super.init()
    }
}
