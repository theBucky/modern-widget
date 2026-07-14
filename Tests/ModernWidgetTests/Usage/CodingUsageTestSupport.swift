import Foundation

@testable import ModernWidget

extension CodingUsageAgentSummary {
    var totals: CodingUsageTotals {
        days.reduce(into: CodingUsageTotals()) { total, day in
            total.add(day.totals)
        }
    }
}

func codingUsageScope(
    now: Date = date(2026, 6, 18, 12)
) -> CodingUsageDateScope {
    CodingUsageDateScope(now: now, calendar: gregorianUTC(firstWeekday: 2))
}

func loadCodingUsage(
    from home: URL,
    environment: [String: String] = [:],
    scope: CodingUsageDateScope = codingUsageScope()
) -> CodingUsageReport {
    let loader = CodingUsageLoader(environment: environment, homeDirectory: home)
    return loader.loadReport(scan: loader.usageScan(scope: scope))
}

func codingUsageTotals(
    in report: CodingUsageReport,
    for agent: CodingUsageAgent
) -> CodingUsageTotals {
    guard let summary = report.agents.first(where: { $0.agent == agent }) else {
        preconditionFailure("missing \(agent) usage summary")
    }
    return summary.totals
}

func writeCodingUsageFixture(
    _ text: String,
    to relativePath: String,
    in root: URL,
    modifiedAt: Date = date(2026, 6, 18, 12)
) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try text.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.modificationDate: modifiedAt],
        ofItemAtPath: url.path
    )
}
