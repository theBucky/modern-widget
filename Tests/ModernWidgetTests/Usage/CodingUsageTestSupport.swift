import Foundation

@testable import ModernWidget

extension CodingUsageLoader {
    func loadReport(scope: CodingUsageDateScope) -> CodingUsageReport {
        loadReport(scan: usageScan(scope: scope))
    }
}

extension CodingUsageAgentSummary {
    var totalCounts: CodingTokenCounts {
        dailyCounts.reduce(into: CodingTokenCounts()) { total, day in
            total.add(day.counts)
        }
    }
}

extension CodingUsageReport {
    var hasUsage: Bool {
        agents.contains { summary in
            summary.dailyCounts.contains { $0.counts.hasUsage }
        }
    }
}
