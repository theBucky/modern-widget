import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isUpdateAvailable = false

    private override init() {
        super.init()

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func start() {
        #if DEBUG
            return
        #else
            controller.startUpdater()
            controller.updater.checkForUpdateInformation()
        #endif
    }

    func checkForUpdates() {
        #if DEBUG
            return
        #else
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            controller.checkForUpdates(nil)
        #endif
    }
}

extension UpdaterManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        isUpdateAvailable = true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        isUpdateAvailable = false
    }
}
