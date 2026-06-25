import SwiftUI

struct MenuBarPanelView: View {
    let engine: ReminderEngine
    let walkHistoryStore: WalkHistoryStore
    let dailySupplementStore: DailySupplementStore
    let usageStore: CodingUsageStore

    @State private var selectedPane = Pane.timer
    @State private var displayedPane = Pane.timer
    @State private var contentOpacity = 1.0
    @State private var paneTransitionID = 0

    private enum Pane: CaseIterable {
        case timer
        case calendar
        case usage

        var title: String {
            switch self {
            case .timer:
                return "Timer"
            case .calendar:
                return "Calendar"
            case .usage:
                return "Usage"
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
            }
        }

        var width: CGFloat {
            switch self {
            case .timer:
                return Layout.mainPaneWidth
            case .calendar, .usage:
                return Layout.detailPaneWidth
            }
        }
    }

    private enum Layout {
        static let mainPaneWidth: CGFloat = 180
        static let detailPaneWidth: CGFloat = 280
        static let borderPadding: CGFloat = 20
        static let unitSpacing: CGFloat = 20
        static let fadeOutAnimation = Animation.easeOut(duration: 0.06)
        static let paneAnimation = Animation.smooth(duration: 0.11)
        static let fadeInAnimation = Animation.easeIn(duration: 0.06)
    }

    var body: some View {
        VStack(spacing: Layout.unitSpacing) {
            panePicker
            paneBody
                .opacity(contentOpacity)
            UpdateAvailableButton()
        }
        .frame(width: displayedPane.width)
        .padding(Layout.borderPadding)
        .onChange(of: selectedPane) { _, newPane in
            switchPane(to: newPane)
        }
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
        }
    }

    private var panePicker: some View {
        Picker("Pane", selection: $selectedPane) {
            ForEach(Pane.allCases, id: \.self) { pane in
                Label(pane.title, systemImage: pane.systemImage).tag(pane)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .labelsHidden()
    }

    private func switchPane(to pane: Pane) {
        paneTransitionID += 1
        let transitionID = paneTransitionID

        guard pane != displayedPane else {
            withAnimation(Layout.fadeInAnimation) {
                contentOpacity = 1
            }
            return
        }

        withAnimation(Layout.fadeOutAnimation) {
            contentOpacity = 0
        } completion: {
            guard paneTransitionID == transitionID else {
                return
            }

            withAnimation(Layout.paneAnimation) {
                displayedPane = pane
            } completion: {
                guard paneTransitionID == transitionID else {
                    return
                }

                withAnimation(Layout.fadeInAnimation) {
                    contentOpacity = 1
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
