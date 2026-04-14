import SwiftUI

@main
struct ModernWidgetApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra(appModel.menuBarTitle) {
            MenuBarContentView(appModel: appModel)
        }
        .menuBarExtraStyle(.window)
    }
}
