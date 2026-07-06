import SwiftUI

struct SettingsPaneView: View {
    @Bindable var store: CodingUsageStore

    @Environment(LaunchAtLoginManager.self) private var launchAtLoginManager
    @Environment(UpdaterManager.self) private var updaterManager

    var body: some View {
        @Bindable var loginManager = launchAtLoginManager

        Form {
            Section("Coding Usage") {
                ForEach(CodingUsageAgent.allCases, id: \.self) { agent in
                    Toggle(isOn: $store[agentActive: agent]) {
                        Text(agent.title)
                    }
                    .toggleStyle(.switch)
                    .disabled(!store.installedAgents.contains(agent))
                }

                Picker("Refresh Interval", selection: $store.refreshInterval) {
                    ForEach(CodingUsageRefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("System") {
                Toggle("Launch at Login", isOn: $loginManager.launchAtLogin)
                    .toggleStyle(.switch)
                    .disabled(!loginManager.canChange)

                LabeledContent("Build", value: Self.buildVersion)

                Button {
                    updaterManager.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
                .disabled(!updaterManager.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            launchAtLoginManager.refresh()
        }
    }

    private static let buildVersion: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }()
}
