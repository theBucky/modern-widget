import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine: ReminderEngine
    private let menuBarViewModel: MenuBarViewModel
    private let menuBarController: MenuBarController

    override init() {
        let engine = ReminderEngine()
        let menuBarViewModel = MenuBarViewModel(engine: engine)
        self.engine = engine
        self.menuBarViewModel = menuBarViewModel
        self.menuBarController = MenuBarController(
            engine: engine,
            menuBarViewModel: menuBarViewModel
        )
        super.init()
    }
}
