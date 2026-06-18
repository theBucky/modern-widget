import SwiftUI

@main
@MainActor
struct ModernWidgetApp: App {
    @State private var engine = ReminderEngine()
    @State private var usageStore = CodingUsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(engine: engine, usageStore: usageStore)
        } label: {
            MenuBarIconView(engine: engine)
                .accessibilityLabel("ModernWidget")
        }
        .menuBarExtraStyle(.window)
    }
}
