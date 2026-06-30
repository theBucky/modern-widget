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
            let suffix: String
            switch agent {
            case .claude:
                suffix = "claude"
            case .codex:
                suffix = "codex"
            case .pi:
                suffix = "pi"
            }
            return "codingUsage.enabledAgent.\(suffix)"
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
            report = report.showingAgents(enabledAgents)
            restartRefresh()
        }
    }

    var refreshInterval: CodingUsageRefreshInterval {
        didSet {
            defaults.set(refreshInterval.rawValue, forKey: DefaultsKey.refreshInterval)
            restartRefresh()
        }
    }

    /// Bool projection per agent so SwiftUI binds through `$store[agentEnabled:]`
    /// instead of fabricating a get/set closure binding on every body pass.
    subscript(agentEnabled agent: CodingUsageAgent) -> Bool {
        get { enabledAgents.contains(agent) }
        set {
            if newValue {
                enabledAgents.insert(agent)
            } else {
                enabledAgents.remove(agent)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedEnabledAgents = Set(
            CodingUsageAgent.allCases.filter { agent in
                defaults.object(forKey: DefaultsKey.enabledAgent(agent)) as? Bool ?? true
            }
        )
        enabledAgents = storedEnabledAgents
        report = CodingUsageReport.empty.showingAgents(storedEnabledAgents)
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
