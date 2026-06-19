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
    }

    var body: some View {
        VStack(spacing: Layout.unitSpacing) {
            panePicker
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

    private var panePicker: some View {
        Picker("Pane", selection: $selectedPane) {
            Label("Timer", systemImage: "timer").tag(Pane.main)
            Label("Calendar", systemImage: "calendar").tag(Pane.calendar)
            Label("Usage", systemImage: "chart.line.uptrend.xyaxis").tag(Pane.usage)
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .labelsHidden()
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
