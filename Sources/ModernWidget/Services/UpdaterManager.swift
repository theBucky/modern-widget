import AppKit
import Combine
import Foundation
import Observation
import Sparkle

/// Sparkle is disabled in debug builds: the bundle is unsigned and runs out of `.build`.
#if DEBUG
    private let usesSparkle = false
#else
    private let usesSparkle = true
#endif

@MainActor
@Observable
final class UpdaterManager: NSObject {
    static let shared = UpdaterManager()

    private(set) var canCheckForUpdates = false
    private(set) var isUpdateAvailable = false

    @ObservationIgnored
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
    )
    @ObservationIgnored
    private var activationPolicyBeforeUpdateUI: NSApplication.ActivationPolicy?

    private override init() {
        super.init()

        guard usesSparkle else {
            return
        }

        // The singleton lives for the app's lifetime, so the task is never cancelled.
        let updater = controller.updater
        Task { @MainActor [weak self] in
            for await canCheck in updater.publisher(for: \.canCheckForUpdates).values {
                self?.canCheckForUpdates = canCheck
            }
        }
    }

    func start() {
        guard usesSparkle else {
            return
        }

        controller.startUpdater()
        controller.updater.checkForUpdateInformation()
    }

    func checkForUpdates() {
        guard usesSparkle else {
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
