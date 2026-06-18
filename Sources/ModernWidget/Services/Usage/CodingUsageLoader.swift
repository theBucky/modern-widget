import Foundation

struct CodingUsageScan: Sendable {
    let scope: CodingUsageDateScope
    let fingerprint: CodingUsageFingerprint
    let claudeFiles: [URL]
    let codexSources: [CodexUsageSource]
    let piFiles: [URL]
}

struct CodingUsageFingerprint: Equatable, Sendable {
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

    func usageScan(scope: CodingUsageDateScope) -> CodingUsageScan {
        let claudeFiles = claudeUsageFiles(scope: scope)
        let codexSources = codexUsageSources(scope: scope)
        let piFiles = piUsageFiles(scope: scope)
        let codexConfigFiles = codexHomeDirectories().map {
            $0.appendingPathComponent("config.toml")
        }
        let files = (claudeFiles + codexSources.flatMap(\.files) + piFiles + codexConfigFiles)
            .uniquedByPath()
            .compactMap(usageFileFingerprint)
            .sorted { $0.path < $1.path }
        let fingerprint = CodingUsageFingerprint(
            historyStart: scope.history.start,
            historyEnd: scope.history.end,
            files: files
        )

        return CodingUsageScan(
            scope: scope,
            fingerprint: fingerprint,
            claudeFiles: claudeFiles,
            codexSources: codexSources,
            piFiles: piFiles
        )
    }

    func loadReport(scope: CodingUsageDateScope) -> CodingUsageReport {
        loadReport(scan: usageScan(scope: scope))
    }

    func loadReport(scan: CodingUsageScan) -> CodingUsageReport {
        var accumulator = CodingUsageAccumulator(scope: scan.scope)
        loadClaudeUsage(files: scan.claudeFiles, scope: scan.scope, into: &accumulator)
        loadCodexUsage(sources: scan.codexSources, into: &accumulator)
        loadPiUsage(files: scan.piFiles, into: &accumulator)

        return CodingUsageReport(
            generatedAt: scan.scope.now,
            agents: accumulator.agentSummaries()
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

    func agentSummaries() -> [CodingUsageAgentSummary] {
        CodingUsageAgent.allCases.map { agent in
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
