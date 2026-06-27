import SwiftUI

struct SettingsPaneView: View {
    let store: CodingUsageStore

    @ObservedObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    @ObservedObject private var updaterManager = UpdaterManager.shared

    var body: some View {
        Form {
            Section("Coding Usage") {
                ForEach(CodingUsageAgent.allCases, id: \.self) { agent in
                    Toggle(
                        agent.title,
                        isOn: Binding(
                            get: { store.enabledAgents.contains(agent) },
                            set: { isEnabled in
                                store.setAgent(agent, enabled: isEnabled)
                            }
                        )
                    )
                    .toggleStyle(.switch)
                }

                Picker(
                    "Refresh Interval",
                    selection: Binding(
                        get: { store.refreshInterval },
                        set: { store.setRefreshInterval($0) }
                    )
                ) {
                    ForEach(CodingUsageRefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("System") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { launchAtLoginManager.isEnabled },
                        set: { launchAtLoginManager.setEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(!launchAtLoginManager.canChange)

                LabeledContent("Build", value: buildVersion)

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

    private var buildVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
