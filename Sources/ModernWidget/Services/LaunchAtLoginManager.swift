import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    /// SMAppService needs a signed bundle in a stable location; debug builds run out
    /// of `.build`, so registration is unavailable there.
    #if DEBUG
        static let isSupported = false
    #else
        static let isSupported = true
    #endif

    private var status = false

    private init() {
        refresh()
    }

    var isEnabled: Bool {
        get { status }
        set {
            guard Self.isSupported else {
                return
            }
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // ignored: refresh reconciles with the real registration status
            }
            refresh()
        }
    }

    /// Re-reads the registration status, catching changes made in System Settings.
    func refresh() {
        guard Self.isSupported else {
            return
        }
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            status = true
        case .notFound, .notRegistered:
            status = false
        @unknown default:
            status = false
        }
    }
}
