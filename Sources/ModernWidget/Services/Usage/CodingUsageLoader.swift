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
    let parseCache: CodingUsageParseCache

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.parseCache = CodingUsageParseCache()
    }

    func installedAgents() -> Set<CodingUsageAgent> {
        installedAgents(
            claudeDirectories: claudeConfigDirectories(),
            codexHomes: codexHomeDirectories(),
            piDirectories: piUsageDirectories()
        )
    }

    private func installedAgents(
        claudeDirectories: [URL],
        codexHomes: [URL],
        piDirectories: [URL]
    ) -> Set<CodingUsageAgent> {
        var installed: Set<CodingUsageAgent> = []
        if !claudeDirectories.isEmpty {
            installed.insert(.claude)
        }
        if !codexHomes.isEmpty {
            installed.insert(.codex)
        }
        if !piDirectories.isEmpty {
            installed.insert(.pi)
        }
        return installed
    }

    func usageScan(
        scope: CodingUsageDateScope,
        enabledAgents: Set<CodingUsageAgent> = Set(CodingUsageAgent.allCases)
    ) -> CodingUsageScan {
        let claudeDirectories = claudeConfigDirectories()
        let codexHomes = codexHomeDirectories()
        let piDirectories = piUsageDirectories()
        let installedAgents = installedAgents(
            claudeDirectories: claudeDirectories,
            codexHomes: codexHomes,
            piDirectories: piDirectories
        )
        let activeAgents = enabledAgents.intersection(installedAgents)
        let claudeFiles =
            activeAgents.contains(.claude)
            ? claudeUsageFiles(in: claudeDirectories, scope: scope) : []
        let codexSources =
            activeAgents.contains(.codex) ? codexUsageSources(homes: codexHomes, scope: scope) : []
        let piFiles =
            activeAgents.contains(.pi) ? piUsageFiles(in: piDirectories, scope: scope) : []
        let extraCodexFiles =
            activeAgents.contains(.codex) ? codexFingerprintFiles(homes: codexHomes) : []
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
    private var dailyCounts: [CodingUsageAgent: [CodingTokenCounts]] = [:]

    init(scope: CodingUsageDateScope) {
        self.scope = scope
    }

    mutating func add(
        _ agent: CodingUsageAgent, counts tokenCounts: CodingTokenCounts, at date: Date
    ) {
        guard let dayIndex = scope.historyDayIndex(containing: date) else {
            return
        }
        let dayCount = scope.historyDays.count
        dailyCounts[
            agent,
            default: Array(repeating: CodingTokenCounts(), count: dayCount),
        ][dayIndex].add(tokenCounts)
    }

    func agentSummaries(for agents: [CodingUsageAgent]) -> [CodingUsageAgentSummary] {
        agents.map { agent in
            CodingUsageAgentSummary(
                agent: agent,
                dailyCounts: scope.historyDays.enumerated().map { index, day in
                    CodingUsageDaySummary(
                        date: day,
                        counts: dailyCounts[agent]?[index] ?? CodingTokenCounts()
                    )
                }
            )
        }
    }
}
