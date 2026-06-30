import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private(set) var isEnabled = false
    private init() {
        refresh()
    }

    var canChange: Bool {
        #if DEBUG
            false
        #else
            true
        #endif
    }

    /// Settable projection for SwiftUI bindings; assigning runs the SMAppService work
    /// and reconciles `isEnabled` with the real registration status.
    var launchAtLogin: Bool {
        get { isEnabled }
        set { setEnabled(newValue) }
    }

    func refresh() {
        #if DEBUG
            isEnabled = false
        #else
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval:
                isEnabled = true
            case .notFound, .notRegistered:
                isEnabled = false
            @unknown default:
                isEnabled = false
            }
        #endif
    }

    private func setEnabled(_ enabled: Bool) {
        #if DEBUG
            refresh()
        #else
            defer {
                refresh()
            }

            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // ignored: the defer refresh reconciles isEnabled with the real status
            }
        #endif
    }
}
