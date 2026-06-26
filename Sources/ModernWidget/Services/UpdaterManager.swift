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
        userDriverDelegate: self
    )

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isUpdateAvailable = false

    private var activationPolicyBeforeUpdateUI: NSApplication.ActivationPolicy?

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
            activateForUpdateUI()
            controller.checkForUpdates(nil)
        #endif
    }

    private func activateForUpdateUI() {
        let currentPolicy = NSApp.activationPolicy()
        if currentPolicy != .regular, activationPolicyBeforeUpdateUI == nil {
            guard NSApp.setActivationPolicy(.regular) else {
                return
            }
            activationPolicyBeforeUpdateUI = currentPolicy
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreActivationPolicy() {
        guard let activationPolicyBeforeUpdateUI else {
            return
        }

        self.activationPolicyBeforeUpdateUI = nil
        NSApp.setActivationPolicy(activationPolicyBeforeUpdateUI)
    }
}

extension UpdaterManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        isUpdateAvailable = true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        isUpdateAvailable = false
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        restoreActivationPolicy()
    }
}

extension UpdaterManager: @preconcurrency SPUStandardUserDriverDelegate {
    func standardUserDriverWillFinishUpdateSession() {
        restoreActivationPolicy()
    }
}
