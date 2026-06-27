import SwiftUI

struct MenuBarPanelView: View {
    let engine: ReminderEngine
    let walkHistoryStore: WalkHistoryStore
    let dailySupplementStore: DailySupplementStore
    let usageStore: CodingUsageStore

    @State private var paneTransition = PaneTransition(initialPane: .timer)

    private enum Pane {
        case timer
        case calendar
        case usage
        case settings

        var title: String {
            switch self {
            case .timer:
                return "Timer"
            case .calendar:
                return "Calendar"
            case .usage:
                return "Usage"
            case .settings:
                return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .timer:
                return "timer"
            case .calendar:
                return "calendar"
            case .usage:
                return "chart.line.uptrend.xyaxis"
            case .settings:
                return "gearshape"
            }
        }

        var width: CGFloat {
            switch self {
            case .timer:
                return PanelLayout.mainPaneWidth
            case .calendar, .usage, .settings:
                return PanelLayout.detailPaneWidth
            }
        }

        static let pickerCases: [Pane] = [.timer, .calendar, .usage]
    }

    private struct PaneTransition {
        var selectedPane: Pane
        var displayedPane: Pane
        var contentOpacity = 1.0

        private var transitionID = 0

        init(initialPane: Pane) {
            self.selectedPane = initialPane
            self.displayedPane = initialPane
        }

        mutating func beginSwitch(to pane: Pane) -> Int? {
            selectedPane = pane
            transitionID += 1

            guard pane != displayedPane else {
                return nil
            }
            return transitionID
        }

        func matches(_ id: Int) -> Bool {
            transitionID == id
        }

        mutating func displaySelectedPane() {
            displayedPane = selectedPane
        }
    }

    private enum Layout {
        static let fadeOutAnimation = Animation.easeOut(duration: 0.06)
        static let paneAnimation = Animation.smooth(duration: 0.11)
        static let fadeInAnimation = Animation.easeIn(duration: 0.06)
    }

    var body: some View {
        VStack(spacing: PanelLayout.paneSpacing) {
            topBar
            paneBody
                .opacity(paneTransition.contentOpacity)
            UpdateAvailableButton()
        }
        .frame(width: paneTransition.displayedPane.width)
        .padding(PanelLayout.outerPadding)
    }

    @ViewBuilder
    private var paneBody: some View {
        switch paneTransition.displayedPane {
        case .timer:
            ReminderPaneView(
                engine: engine,
                walkHistoryStore: walkHistoryStore,
                dailySupplementStore: dailySupplementStore
            )
        case .calendar:
            WalkHistoryCalendarView(
                historyStore: walkHistoryStore,
                supplementStore: dailySupplementStore
            )
        case .usage:
            CodingUsageView(store: usageStore)
        case .settings:
            SettingsPaneView(store: usageStore)
        }
    }

    private var topBar: some View {
        HStack {
            panePicker
            Spacer()
            Button {
                switchPane(to: .settings)
            } label: {
                Image(systemName: Pane.settings.systemImage)
            }
            .buttonStyle(.borderless)
            .help(Pane.settings.title)
        }
        .frame(maxWidth: .infinity)
    }

    private var panePicker: some View {
        Picker(
            "Pane",
            selection: Binding(
                get: { paneTransition.selectedPane },
                set: { pane in switchPane(to: pane) }
            )
        ) {
            ForEach(Pane.pickerCases, id: \.self) { pane in
                Label(pane.title, systemImage: pane.systemImage).tag(pane)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .labelsHidden()
    }

    private func switchPane(to pane: Pane) {
        guard let transitionID = paneTransition.beginSwitch(to: pane) else {
            withAnimation(Layout.fadeInAnimation) {
                paneTransition.contentOpacity = 1
            }
            return
        }

        withAnimation(Layout.fadeOutAnimation) {
            paneTransition.contentOpacity = 0
        } completion: {
            guard paneTransition.matches(transitionID) else {
                return
            }

            withAnimation(Layout.paneAnimation) {
                paneTransition.displaySelectedPane()
            } completion: {
                guard paneTransition.matches(transitionID) else {
                    return
                }

                withAnimation(Layout.fadeInAnimation) {
                    paneTransition.contentOpacity = 1
                }
            }
        }
    }
}

private struct UpdateAvailableButton: View {
    @ObservedObject private var updaterManager = UpdaterManager.shared

    var body: some View {
        if updaterManager.isUpdateAvailable {
            Button {
                updaterManager.checkForUpdates()
            } label: {
                Label("Update Available", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!updaterManager.canCheckForUpdates)
            .help("Update Available")
        }
    }
}
