import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterManager = UpdaterManager()

    func applicationDidFinishLaunching(_: Notification) {
        updaterManager.start()
    }
}
