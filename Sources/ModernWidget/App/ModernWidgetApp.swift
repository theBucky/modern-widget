import SwiftUI

@main
@MainActor
struct ModernWidgetApp: App {
    @State private var engine = ReminderEngine()
    @State private var walkHistoryStore = WalkHistoryStore()
    @State private var dailySupplementStore = DailySupplementStore()
    @State private var usageStore = CodingUsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView(
                engine: engine,
                walkHistoryStore: walkHistoryStore,
                dailySupplementStore: dailySupplementStore,
                usageStore: usageStore
            )
        } label: {
            MenuBarIconView(engine: engine)
                .accessibilityLabel("ModernWidget")
        }
        .menuBarExtraStyle(.window)
    }
}
