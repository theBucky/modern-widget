import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled = false
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

    func setEnabled(_ enabled: Bool) {
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
                return
            }
        #endif
    }
}
