import AppKit
import Combine
import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class UpdaterManager: NSObject {
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

    private(set) var canCheckForUpdates = false
    private(set) var isUpdateAvailable = false

    /// The menu bar "Update" badge is shown when an update is waiting and enabled when
    /// the updater is ready to act. DEBUG forces both on so the layout previews without
    /// a real Sparkle update; that override lives only in `previewsBadge`.
    var updateBadgeVisible: Bool {
        previewsBadge || isUpdateAvailable
    }

    var updateBadgeEnabled: Bool {
        previewsBadge || canCheckForUpdates
    }

    private var previewsBadge: Bool {
        BuildMode.previewsUpdateAvailableBadge
    }

    @ObservationIgnored
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
    )
    @ObservationIgnored
    private var canCheckObservation: AnyCancellable?
    @ObservationIgnored
    private var activationPolicyBeforeUpdateUI: NSApplication.ActivationPolicy?

    private override init() {
        super.init()

        guard BuildMode.usesSparkle else {
            return
        }

        canCheckObservation = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] canCheck in
                Task { @MainActor in
                    self?.canCheckForUpdates = canCheck
                }
            }
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
