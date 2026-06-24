import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updaterManager = UpdaterManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        updaterManager.start()
    }
}
