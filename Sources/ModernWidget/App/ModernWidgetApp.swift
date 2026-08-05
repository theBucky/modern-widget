import SwiftUI

@main
@MainActor
struct ModernWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var engine = ReminderEngine()
    @State private var walkHistoryStore = WalkHistoryStore()
    @State private var dailySupplementStore = DailySupplementStore()
    @State private var usageStore = CodingUsageStore()
    @State private var launchAtLoginManager = LaunchAtLoginManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView()
                .environment(engine)
                .environment(walkHistoryStore)
                .environment(dailySupplementStore)
                .environment(usageStore)
                .environment(appDelegate.updaterManager)
                .environment(launchAtLoginManager)
        } label: {
            MenuBarIconView(engine: engine)
                .accessibilityLabel("ModernWidget")
        }
        .menuBarExtraStyle(.window)
    }
}
