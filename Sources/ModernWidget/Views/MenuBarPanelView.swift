import SwiftUI

private enum Pane: Hashable {
    case timer
    case calendar
    case usage
    case settings

    var title: LocalizedStringResource {
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

struct MenuBarPanelView: View {
    @State private var selectedPane: Pane = .timer

    var body: some View {
        VStack(spacing: PanelLayout.paneSpacing) {
            // The switch must run in a real transaction (Binding.animation): a scoped
            // `.animation(value:)` crossfades the panes but lets the MenuBarExtra
            // window snap to the new width instead of tracking it.
            PanelTopBar(selection: $selectedPane.animation(.smooth(duration: 0.2)))
            // The ZStack overlays the outgoing and incoming panes during the crossfade;
            // as direct VStack children they would stack vertically and jump the layout.
            ZStack(alignment: .top) {
                PaneBody(pane: selectedPane)
                    .id(selectedPane)
                    .transition(.opacity)
            }
        }
        .frame(width: selectedPane.width)
        .padding(PanelLayout.outerPadding)
    }
}

private struct PaneBody: View {
    let pane: Pane

    var body: some View {
        switch pane {
        case .timer:
            ReminderPaneView()
        case .calendar:
            WalkHistoryCalendarView()
        case .usage:
            CodingUsageView()
        case .settings:
            SettingsPaneView()
        }
    }
}

private struct PanelTopBar: View {
    @Binding var selection: Pane

    var body: some View {
        HStack {
            Picker("Pane", selection: $selection) {
                ForEach(Pane.pickerCases, id: \.self) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.systemImage)
                    }
                    .tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()

            Spacer()
            UpdateAvailableButton()
            Button {
                selection = .settings
            } label: {
                Image(systemName: Pane.settings.systemImage)
            }
            .buttonStyle(.borderless)
            .help(Text(Pane.settings.title))
        }
    }
}

private struct UpdateAvailableButton: View {
    @Environment(UpdaterManager.self) private var updaterManager

    var body: some View {
        if updaterManager.updateBadgeVisible {
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
            .disabled(!updaterManager.updateBadgeEnabled)
            .help("Update Available")
        }
    }
}
