import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    private enum BuildMode {
        #if DEBUG
            static let usesSparkle = false
            static let previewsUpdateAvailableBadge = true
        #else
            static let usesSparkle = true
            static let previewsUpdateAvailableBadge = false
        #endif
    }

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
    )

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isUpdateAvailable = false

    var showsUpdateAvailableBadge: Bool {
        BuildMode.previewsUpdateAvailableBadge || isUpdateAvailable
    }

    var canUseUpdateAvailableBadge: Bool {
        BuildMode.previewsUpdateAvailableBadge || canCheckForUpdates
    }

    private var activationPolicyBeforeUpdateUI: NSApplication.ActivationPolicy?

    private override init() {
        super.init()

        guard BuildMode.usesSparkle else {
            return
        }

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func start() {
        guard BuildMode.usesSparkle else {
            return
        }

        controller.startUpdater()
        controller.updater.checkForUpdateInformation()
    }

    func checkForUpdates() {
        guard BuildMode.usesSparkle else {
            return
        }

        activateForUpdateUI()
        controller.checkForUpdates(nil)
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
        guard let previousPolicy = activationPolicyBeforeUpdateUI else {
            return
        }

        activationPolicyBeforeUpdateUI = nil
        NSApp.setActivationPolicy(previousPolicy)
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
