import SwiftUI

struct MenuBarPanelView: View {
    private let engine: ReminderEngine
    private let walkHistoryStore: WalkHistoryStore
    private let dailySupplementStore: DailySupplementStore
    private let usageStore: CodingUsageStore

    @State private var selectedPane = Pane.main

    init(
        engine: ReminderEngine,
        walkHistoryStore: WalkHistoryStore,
        dailySupplementStore: DailySupplementStore,
        usageStore: CodingUsageStore
    ) {
        self.engine = engine
        self.walkHistoryStore = walkHistoryStore
        self.dailySupplementStore = dailySupplementStore
        self.usageStore = usageStore
    }

    private enum Pane {
        case main
        case calendar
        case usage
    }

    private enum Layout {
        static let mainPaneWidth: CGFloat = 180
        static let detailPaneWidth: CGFloat = 280
        static let borderPadding: CGFloat = 20
        static let unitSpacing: CGFloat = 20
        static let tabIconSize: CGFloat = 22
    }

    var body: some View {
        VStack(spacing: Layout.unitSpacing) {
            tabBar
            paneBody
                .id(selectedPane)
                .transition(.opacity)
        }
        .frame(width: paneWidth)
        .padding(Layout.borderPadding)
        .animation(.smooth(duration: 0.18), value: selectedPane)
    }

    @ViewBuilder
    private var paneBody: some View {
        switch selectedPane {
        case .main:
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

    private var paneWidth: CGFloat {
        switch selectedPane {
        case .main:
            return Layout.mainPaneWidth
        case .calendar, .usage:
            return Layout.detailPaneWidth
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            paneButton(.main, systemImage: "timer")
            paneButton(.calendar, systemImage: "calendar")
            paneButton(.usage, systemImage: "chart.line.uptrend.xyaxis")
        }
        .frame(maxWidth: .infinity)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func paneButton(_ pane: Pane, systemImage: String) -> some View {
        Button {
            selectedPane = pane
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: Layout.tabIconSize, height: Layout.tabIconSize)
                .foregroundStyle(selectedPane == pane ? Color.accentColor : .secondary)
        }
        .buttonStyle(.borderless)
    }
}
