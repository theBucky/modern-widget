import SwiftUI

struct MenuBarPanelView: View {
    let engine: ReminderEngine
    let walkHistoryStore: WalkHistoryStore
    let dailySupplementStore: DailySupplementStore
    let usageStore: CodingUsageStore

    @State private var selectedPane: Pane = .timer
    @State private var displayedPane: Pane = .timer
    @State private var contentOpacity = 1.0
    @State private var transitionID = 0

    private enum Pane: Hashable {
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

    private enum PaneTransitionAnimation {
        static let fadeOut = Animation.easeOut(duration: 0.06)
        static let swap = Animation.smooth(duration: 0.11)
        static let fadeIn = Animation.easeIn(duration: 0.06)
    }

    var body: some View {
        VStack(spacing: PanelLayout.paneSpacing) {
            topBar
            paneBody
                .opacity(contentOpacity)
        }
        .frame(width: displayedPane.width)
        .padding(PanelLayout.outerPadding)
    }

    @ViewBuilder
    private var paneBody: some View {
        switch displayedPane {
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
            UpdateAvailableButton()
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
                get: { selectedPane },
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
        selectedPane = pane
        // A newer switch bumps transitionID, so completion handlers from an interrupted
        // transition bail out instead of swapping or fading a superseded pane.
        transitionID += 1
        let activeTransition = transitionID

        guard pane != displayedPane else {
            withAnimation(PaneTransitionAnimation.fadeIn) {
                contentOpacity = 1
            }
            return
        }

        withAnimation(PaneTransitionAnimation.fadeOut) {
            contentOpacity = 0
        } completion: {
            guard transitionID == activeTransition else {
                return
            }

            withAnimation(PaneTransitionAnimation.swap) {
                displayedPane = selectedPane
            } completion: {
                guard transitionID == activeTransition else {
                    return
                }

                withAnimation(PaneTransitionAnimation.fadeIn) {
                    contentOpacity = 1
                }
            }
        }
    }
}

private struct UpdateAvailableButton: View {
    @ObservedObject private var updaterManager = UpdaterManager.shared

    var body: some View {
        if updaterManager.showsUpdateAvailableBadge {
            Button {
                updaterManager.checkForUpdates()
            } label: {
                Text("Update")
                    .font(.caption2.weight(.semibold))
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.mini)
            .disabled(!updaterManager.canUseUpdateAvailableBadge)
            .help("Update Available")
        }
    }
}
