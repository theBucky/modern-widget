import Foundation
import Observation

enum CodingUsageRefreshInterval: Int, CaseIterable, Identifiable {
    case tenMinutes = 600
    case thirtyMinutes = 1800
    case oneHour = 3600

    var id: Self { self }

    var title: String {
        switch self {
        case .tenMinutes:
            return "10 min"
        case .thirtyMinutes:
            return "30 min"
        case .oneHour:
            return "1 hour"
        }
    }
}

@MainActor
@Observable
final class CodingUsageStore {
    private enum DefaultsKey {
        static let refreshInterval = "codingUsage.refreshInterval"

        static func enabledAgent(_ agent: CodingUsageAgent) -> String {
            "codingUsage.enabledAgent.\(agent.defaultsName)"
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    private(set) var report = CodingUsageReport.empty
    var enabledAgents: Set<CodingUsageAgent> {
        didSet {
            for agent in CodingUsageAgent.allCases {
                defaults.set(enabledAgents.contains(agent), forKey: DefaultsKey.enabledAgent(agent))
            }
        }
    }

    var refreshInterval: CodingUsageRefreshInterval {
        didSet {
            defaults.set(refreshInterval.rawValue, forKey: DefaultsKey.refreshInterval)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabledAgents = Set(
            CodingUsageAgent.allCases.filter { agent in
                defaults.object(forKey: DefaultsKey.enabledAgent(agent)) as? Bool ?? true
            }
        )
        refreshInterval =
            CodingUsageRefreshInterval(
                rawValue: defaults.integer(forKey: DefaultsKey.refreshInterval))
            ?? .tenMinutes
        self.loader = CodingUsageLoader()
        startRefreshTask()
    }

    @ObservationIgnored
    private let loader: CodingUsageLoader
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var lastFingerprint: CodingUsageFingerprint?

    deinit {
        refreshTask?.cancel()
    }

    func setAgent(_ agent: CodingUsageAgent, enabled: Bool) {
        if enabled {
            enabledAgents.insert(agent)
        } else {
            enabledAgents.remove(agent)
        }
        restartRefresh()
    }

    func setRefreshInterval(_ refreshInterval: CodingUsageRefreshInterval) {
        self.refreshInterval = refreshInterval
        restartRefresh()
    }

    private func restartRefresh() {
        lastFingerprint = nil
        refreshTask?.cancel()
        startRefreshTask()
    }

    private func startRefreshTask() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                await self.reload()
                do {
                    try await Task.sleep(for: .seconds(refreshInterval.rawValue))
                } catch {
                    return
                }
            }
        }
    }

    private func reload() async {
        let loader = self.loader
        let scope = CodingUsageDateScope()
        let enabledAgents = self.enabledAgents
        let scan = await Task.detached(priority: .utility) {
            loader.usageScan(scope: scope, enabledAgents: enabledAgents)
        }.value

        if Task.isCancelled || scan.fingerprint == lastFingerprint {
            return
        }

        let report = await Task.detached(priority: .utility) {
            loader.loadReport(scan: scan)
        }.value

        if Task.isCancelled {
            return
        }
        lastFingerprint = scan.fingerprint
        self.report = report
    }
}

private extension CodingUsageAgent {
    var defaultsName: String {
        switch self {
        case .claude:
            return "claude"
        case .codex:
            return "codex"
        case .pi:
            return "pi"
        }
    }
}
