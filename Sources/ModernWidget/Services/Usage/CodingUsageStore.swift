import Foundation
import Observation

enum CodingUsageRefreshInterval: Int, CaseIterable, Identifiable {
    case tenMinutes = 600
    case thirtyMinutes = 1800
    case oneHour = 3600

    var id: Self { self }

    var title: LocalizedStringResource {
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
            "codingUsage.enabledAgent.\(agent.rawValue)"
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let loader: CodingUsageLoader
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var lastFingerprint: CodingUsageFingerprint?
    @ObservationIgnored
    private var scope: CodingUsageDateScope
    @ObservationIgnored
    private var report: CodingUsageReport

    private(set) var presentation: CodingUsagePresentation

    var enabledAgents: Set<CodingUsageAgent> {
        didSet {
            for agent in CodingUsageAgent.allCases {
                defaults.set(enabledAgents.contains(agent), forKey: DefaultsKey.enabledAgent(agent))
            }
            presentation = CodingUsagePresentation(
                report: report,
                scope: scope,
                enabledAgents: enabledAgents
            )
            restartRefresh()
        }
    }

    var refreshInterval: CodingUsageRefreshInterval {
        didSet {
            defaults.set(refreshInterval.rawValue, forKey: DefaultsKey.refreshInterval)
            restartRefresh()
        }
    }

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
        self.loader = CodingUsageLoader()
        let storedEnabledAgents = Set(
            CodingUsageAgent.allCases.filter { agent in
                defaults.object(forKey: DefaultsKey.enabledAgent(agent)) as? Bool ?? true
            }
        )
        self.enabledAgents = storedEnabledAgents
        self.refreshInterval =
            CodingUsageRefreshInterval(
                rawValue: defaults.integer(forKey: DefaultsKey.refreshInterval))
            ?? .tenMinutes
        let scope = CodingUsageDateScope()
        let report = CodingUsageReport.placeholder(
            scope: scope,
            agents: CodingUsageAgent.ordered(storedEnabledAgents)
        )
        self.scope = scope
        self.report = report
        self.presentation = CodingUsagePresentation(
            report: report,
            scope: scope,
            enabledAgents: storedEnabledAgents
        )
        startRefreshTask()
    }

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

        let result = await Task.detached(priority: .utility) {
            let report = loader.loadReport(scan: scan)
            let presentation = CodingUsagePresentation(
                report: report,
                scope: scan.scope,
                enabledAgents: enabledAgents
            )
            return (report: report, presentation: presentation)
        }.value

        if Task.isCancelled {
            return
        }
        lastFingerprint = scan.fingerprint
        self.scope = scan.scope
        self.report = result.report
        self.presentation = result.presentation
    }
}
