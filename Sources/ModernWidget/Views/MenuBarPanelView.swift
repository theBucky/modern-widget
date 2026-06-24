import SwiftUI

struct MenuBarPanelView: View {
    let engine: ReminderEngine
    let walkHistoryStore: WalkHistoryStore
    let dailySupplementStore: DailySupplementStore
    let usageStore: CodingUsageStore

    @State private var selectedPane = Pane.main
    @State private var displayedPane = Pane.main
    @State private var intervalMenuIdentity = 0
    @State private var contentOpacity = 1.0
    @State private var paneTransitionID = 0

    private enum Pane: CaseIterable {
        case main
        case calendar
        case usage

        var title: String {
            switch self {
            case .main:
                return "Timer"
            case .calendar:
                return "Calendar"
            case .usage:
                return "Usage"
            }
        }

        var systemImage: String {
            switch self {
            case .main:
                return "timer"
            case .calendar:
                return "calendar"
            case .usage:
                return "chart.line.uptrend.xyaxis"
            }
        }

        var width: CGFloat {
            switch self {
            case .main:
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
        case .main:
            ReminderPaneView(
                engine: engine,
                walkHistoryStore: walkHistoryStore,
                dailySupplementStore: dailySupplementStore,
                intervalMenuIdentity: intervalMenuIdentity
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

                if pane == .main {
                    // Menu bridges to NSPopUpButton; recreate it after resize settles.
                    intervalMenuIdentity += 1
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
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Update Available")
                }
                .font(.caption)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .disabled(!updaterManager.canCheckForUpdates)
            .help("Update Available")
        }
    }
}
