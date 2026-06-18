import Foundation

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

    func loadReport(scope: CodingUsageDateScope) -> CodingUsageReport {
        var accumulator = CodingUsageAccumulator(scope: scope)
        loadClaudeUsage(scope: scope, into: &accumulator)
        loadCodexUsage(scope: scope, into: &accumulator)
        loadPiUsage(scope: scope, into: &accumulator)

        return CodingUsageReport(
            generatedAt: scope.now,
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
