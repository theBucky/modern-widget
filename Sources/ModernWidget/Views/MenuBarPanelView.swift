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
    @State private var displayedPane: Pane = .timer
    @State private var isContentVisible = true

    var body: some View {
        VStack(spacing: PanelLayout.paneSpacing) {
            PanelTopBar(selection: $selectedPane)
            PaneBody(pane: displayedPane)
                .opacity(isContentVisible ? 1 : 0)
        }
        .frame(width: displayedPane.width)
        .padding(PanelLayout.outerPadding)
        .task(id: selectedPane) {
            await transitionToSelectedPane()
        }
    }

    /// A pane switch runs fade out, resize, fade in as one cancellable sequence.
    /// The resize must be its own real transaction (withAnimation) or the
    /// MenuBarExtra window snaps to the new width instead of tracking it, and the
    /// content stays hidden until the resize settles so nothing renders outside
    /// the still-moving window bounds.
    private func transitionToSelectedPane() async {
        let fadeOutDuration = 0.08
        let resizeDuration = 0.1

        do {
            if displayedPane != selectedPane {
                withAnimation(.easeOut(duration: fadeOutDuration)) { isContentVisible = false }
                try await Task.sleep(for: .seconds(fadeOutDuration))

                withAnimation(.smooth(duration: resizeDuration)) { displayedPane = selectedPane }
                // Extra beat past the resize so the spring settles before the reveal.
                try await Task.sleep(for: .seconds(resizeDuration + 0.02))
            }
            withAnimation(.easeOut(duration: 0.12)) { isContentVisible = true }
        } catch {
            // Cancelled by a newer selection: its task converges the state.
        }
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
