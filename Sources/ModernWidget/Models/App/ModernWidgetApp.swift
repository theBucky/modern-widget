import SwiftUI

@main
struct ModernWidgetApp: App {
    private let engine: ReminderEngine
    @StateObject private var menuBarViewModel: MenuBarViewModel

    init() {
        let engine = ReminderEngine()
        self.engine = engine
        _menuBarViewModel = StateObject(wrappedValue: MenuBarViewModel(engine: engine))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(engine: engine)
        } label: {
            MenuBarStatusLabel(viewModel: menuBarViewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        let snapshot = viewModel.snapshot

        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: snapshot.symbolName)
            Text(snapshot.text)
                .monospacedDigit()
        }
    }
}
