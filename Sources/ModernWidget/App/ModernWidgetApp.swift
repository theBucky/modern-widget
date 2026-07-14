import SwiftUI

@main
@MainActor
struct ModernWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var engine: ReminderEngine
    @State private var walkHistoryStore: WalkHistoryStore
    @State private var dailySupplementStore = DailySupplementStore()
    @State private var usageStore = CodingUsageStore()

    init() {
        let engine = ReminderEngine()
        let walkHistoryStore = WalkHistoryStore()
        engine.onBreakCompleted = { walkHistoryStore.recordWalk($0) }
        _engine = State(initialValue: engine)
        _walkHistoryStore = State(initialValue: walkHistoryStore)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView()
                .environment(engine)
                .environment(walkHistoryStore)
                .environment(dailySupplementStore)
                .environment(usageStore)
                .environment(UpdaterManager.shared)
                .environment(LaunchAtLoginManager.shared)
        } label: {
            MenuBarIconView(engine: engine)
                .accessibilityLabel("ModernWidget")
        }
        .menuBarExtraStyle(.window)
    }
}
