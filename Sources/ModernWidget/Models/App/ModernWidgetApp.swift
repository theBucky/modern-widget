import SwiftUI

@main
struct ModernWidgetApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appModel: appModel)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: appModel.menuBarSymbolName)
                Text(appModel.menuBarLabelText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
