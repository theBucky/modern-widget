import Foundation

struct CodingUsageScan: Sendable {
    let scope: CodingUsageDateScope
    let installedAgents: Set<CodingUsageAgent>
    let fingerprint: CodingUsageFingerprint
    let claudeFiles: [CodingUsageFile]
    let codexSources: [CodexUsageSource]
    let piFiles: [CodingUsageFile]
}

struct CodingUsageFingerprint: Equatable, Sendable {
    let agents: [CodingUsageAgent]
    let historyStart: Date
    let historyEnd: Date
    let files: [CodingUsageFileFingerprint]
}

struct CodingUsageLoader: Sendable {
    let environment: [String: String]
    let homeDirectory: URL

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func installedAgents() -> Set<CodingUsageAgent> {
        var installed: Set<CodingUsageAgent> = []
        if !claudeConfigDirectories().isEmpty {
            installed.insert(.claude)
        }
        if !codexHomeDirectories().isEmpty {
            installed.insert(.codex)
        }
        if !piUsageDirectories().isEmpty {
            installed.insert(.pi)
        }
        return installed
    }

    func usageScan(
        scope: CodingUsageDateScope,
        enabledAgents: Set<CodingUsageAgent> = Set(CodingUsageAgent.allCases)
    ) -> CodingUsageScan {
        let installedAgents = installedAgents()
        let activeAgents = enabledAgents.intersection(installedAgents)
        let claudeFiles = activeAgents.contains(.claude) ? claudeUsageFiles(scope: scope) : []
        let codexSources = activeAgents.contains(.codex) ? codexUsageSources(scope: scope) : []
        let piFiles = activeAgents.contains(.pi) ? piUsageFiles(scope: scope) : []
        let extraCodexFiles = activeAgents.contains(.codex) ? codexFingerprintFiles() : []
        let files =
            ((claudeFiles + codexSources.flatMap(\.files) + piFiles).map(\.fingerprint)
            + extraCodexFiles.compactMap(usageFileFingerprint))
            .uniqued(by: \.path)
            .sorted { $0.path < $1.path }
        let fingerprint = CodingUsageFingerprint(
            agents: CodingUsageAgent.ordered(activeAgents),
            historyStart: scope.history.start,
            historyEnd: scope.history.end,
            files: files
        )

        return CodingUsageScan(
            scope: scope,
            installedAgents: installedAgents,
            fingerprint: fingerprint,
            claudeFiles: claudeFiles,
            codexSources: codexSources,
            piFiles: piFiles
        )
    }

    func loadReport(scan: CodingUsageScan) -> CodingUsageReport {
        var accumulator = CodingUsageAccumulator(scope: scan.scope)
        loadClaudeUsage(files: scan.claudeFiles, scope: scan.scope, into: &accumulator)
        loadCodexUsage(sources: scan.codexSources, into: &accumulator)
        loadPiUsage(files: scan.piFiles, into: &accumulator)

        return CodingUsageReport(
            state: .loaded(generatedAt: scan.scope.now),
            agents: accumulator.agentSummaries(for: scan.fingerprint.agents)
        )
    }
}

struct CodingUsageAccumulator {
    private let scope: CodingUsageDateScope
    private var dailyCounts: [CodingUsageAgent: [Date: CodingTokenCounts]] = [:]

    init(scope: CodingUsageDateScope) {
        self.scope = scope
    }

    mutating func add(
        _ agent: CodingUsageAgent, counts tokenCounts: CodingTokenCounts, at date: Date
    ) {
        guard let day = scope.historyDay(containing: date) else {
            return
        }
        dailyCounts[agent, default: [:]][day, default: CodingTokenCounts()].add(tokenCounts)
    }

    func agentSummaries(for agents: [CodingUsageAgent]) -> [CodingUsageAgentSummary] {
        agents.map { agent in
            CodingUsageAgentSummary(
                agent: agent,
                dailyCounts: scope.historyDays.map { day in
                    CodingUsageDaySummary(
                        date: day,
                        counts: dailyCounts[agent]?[day] ?? CodingTokenCounts()
                    )
                }
            )
        }
    }
}
