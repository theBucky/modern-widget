import Foundation

struct CodingUsageScan: Sendable {
    let scope: CodingUsageDateScope
    let installedAgents: Set<CodingUsageAgent>
    let fingerprint: CodingUsageFingerprint
    let claude: ClaudeUsageScan
    let codex: CodexUsageScan
    let pi: PiUsageScan
}

struct CodingUsageFingerprint: Equatable, Sendable {
    let agents: [CodingUsageAgent]
    let historyStart: Date
    let historyEnd: Date
    let files: [CodingUsageFile]
}

private enum CodingUsageProviderScan: Sendable {
    case claude(ClaudeUsageScan)
    case codex(CodexUsageScan)
    case pi(PiUsageScan)
}

struct CodingUsageLoader: Sendable {
    private let claude: ClaudeUsageLoader
    private let codex: CodexUsageLoader
    private let pi: PiUsageLoader

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let fileSystem = CodingUsageFileSystem(
            environment: environment,
            homeDirectory: homeDirectory
        )
        self.claude = ClaudeUsageLoader(fileSystem: fileSystem)
        self.codex = CodexUsageLoader(fileSystem: fileSystem)
        self.pi = PiUsageLoader(fileSystem: fileSystem)
    }

    func installedAgents() -> Set<CodingUsageAgent> {
        var agents: Set<CodingUsageAgent> = []
        if claude.isInstalled() {
            agents.insert(.claude)
        }
        if codex.isInstalled() {
            agents.insert(.codex)
        }
        if pi.isInstalled() {
            agents.insert(.pi)
        }
        return agents
    }

    func usageScan(
        scope: CodingUsageDateScope,
        enabledAgents: Set<CodingUsageAgent> = Set(CodingUsageAgent.allCases)
    ) -> CodingUsageScan {
        let scans: [@Sendable () -> CodingUsageProviderScan] = [
            {
                .claude(
                    claude.scan(scope: scope, enabled: enabledAgents.contains(.claude))
                )
            },
            {
                .codex(
                    codex.scan(scope: scope, enabled: enabledAgents.contains(.codex))
                )
            },
            {
                .pi(pi.scan(scope: scope, enabled: enabledAgents.contains(.pi)))
            },
        ]

        var claudeScan = ClaudeUsageScan(isInstalled: false, files: [])
        var codexScan = CodexUsageScan(isInstalled: false, sources: [])
        var piScan = PiUsageScan(isInstalled: false, files: [])
        for scan in concurrentMap(scans, { $0() }) {
            switch scan {
            case let .claude(value):
                claudeScan = value
            case let .codex(value):
                codexScan = value
            case let .pi(value):
                piScan = value
            }
        }

        var installedAgents: Set<CodingUsageAgent> = []
        if claudeScan.isInstalled {
            installedAgents.insert(.claude)
        }
        if codexScan.isInstalled {
            installedAgents.insert(.codex)
        }
        if piScan.isInstalled {
            installedAgents.insert(.pi)
        }
        let activeAgents = enabledAgents.intersection(installedAgents)
        let files =
            (claudeScan.files + codexScan.sources.flatMap(\.files) + piScan.files)
            .uniqued(by: \.path)
            .sorted { $0.path < $1.path }

        return CodingUsageScan(
            scope: scope,
            installedAgents: installedAgents,
            fingerprint: CodingUsageFingerprint(
                agents: CodingUsageAgent.ordered(activeAgents),
                historyStart: scope.history.start,
                historyEnd: scope.history.end,
                files: files
            ),
            claude: claudeScan,
            codex: codexScan,
            pi: piScan
        )
    }

    func loadReport(scan: CodingUsageScan) -> CodingUsageReport {
        var accumulator = CodingUsageAccumulator(scope: scan.scope)
        for agent in scan.fingerprint.agents {
            switch agent {
            case .claude:
                claude.load(scan.claude, scope: scan.scope) {
                    accumulator.add($0, for: agent)
                }
            case .codex:
                codex.load(scan.codex) {
                    accumulator.add($0, for: agent)
                }
            case .pi:
                pi.load(scan.pi) {
                    accumulator.add($0, for: agent)
                }
            }
        }

        return CodingUsageReport(
            state: .loaded(generatedAt: scan.scope.now),
            agents: accumulator.agentSummaries(for: scan.fingerprint.agents)
        )
    }
}

private struct CodingUsageAccumulator {
    private let scope: CodingUsageDateScope
    private var dailyTotals: [CodingUsageAgent: [CodingUsageTotals]] = [:]

    init(scope: CodingUsageDateScope) {
        self.scope = scope
    }

    mutating func add(_ event: CodingUsageEvent, for agent: CodingUsageAgent) {
        guard let dayIndex = scope.historyDayIndex(containing: event.timestamp) else {
            return
        }
        let dayCount = scope.historyDays.count
        dailyTotals[
            agent,
            default: Array(repeating: CodingUsageTotals(), count: dayCount),
        ][dayIndex].add(event.totals)
    }

    func agentSummaries(for agents: [CodingUsageAgent]) -> [CodingUsageAgentSummary] {
        agents.map { agent in
            CodingUsageAgentSummary(
                agent: agent,
                days: scope.historyDays.enumerated().map { index, day in
                    CodingUsageDaySummary(
                        date: day,
                        totals: dailyTotals[agent]?[index] ?? CodingUsageTotals()
                    )
                }
            )
        }
    }
}
