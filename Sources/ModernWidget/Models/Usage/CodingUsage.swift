import Foundation

enum CodingUsageAgent: CaseIterable, Hashable, Sendable {
    case claude
    case codex
    case pi

    var title: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .pi:
            return "Pi"
        }
    }

    var logoResourceName: String {
        switch self {
        case .claude:
            return "ClaudeLogo"
        case .codex:
            return "CodexLogo"
        case .pi:
            return "PiLogo"
        }
    }
}

struct CodingTokenCounts: Equatable, Sendable {
    var inputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var cacheCreationTokens: UInt64 = 0
    var cacheReadTokens: UInt64 = 0
    var reasoningTokens: UInt64 = 0
    var totalTokens: UInt64 = 0
    var costUSD: Double = 0

    var hasUsage: Bool {
        inputTokens > 0 || outputTokens > 0 || cacheCreationTokens > 0 || cacheReadTokens > 0
            || reasoningTokens > 0 || totalTokens > 0 || costUSD > 0
    }

    mutating func add(_ other: CodingTokenCounts) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationTokens += other.cacheCreationTokens
        cacheReadTokens += other.cacheReadTokens
        reasoningTokens += other.reasoningTokens
        totalTokens += other.totalTokens
        costUSD += other.costUSD
    }

    static func claude(
        inputTokens: UInt64,
        outputTokens: UInt64,
        cacheCreationTokens: UInt64,
        cacheReadTokens: UInt64,
        costUSD: Double
    ) -> Self {
        Self(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens,
            totalTokens: inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens,
            costUSD: costUSD
        )
    }

    static func codex(
        rawInputTokens: UInt64,
        cachedInputTokens: UInt64,
        outputTokens: UInt64,
        reasoningTokens: UInt64,
        costUSD: Double
    ) -> Self {
        Self(
            inputTokens: rawInputTokens.saturatingSubtract(cachedInputTokens),
            outputTokens: outputTokens,
            cacheReadTokens: cachedInputTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: rawInputTokens + outputTokens,
            costUSD: costUSD
        )
    }
}

struct CodingUsageDaySummary: Equatable, Sendable {
    let date: Date
    let counts: CodingTokenCounts
}

struct CodingUsagePeriodRow: Equatable, Sendable {
    let title: String
    let counts: CodingTokenCounts
}

struct CodingUsageAgentSummary: Equatable, Sendable {
    let agent: CodingUsageAgent
    let dailyCounts: [CodingUsageDaySummary]

    var totalCounts: CodingTokenCounts {
        dailyCounts.reduce(into: CodingTokenCounts()) { total, day in
            total.add(day.counts)
        }
    }

    func usageRows(now: Date, calendar: Calendar = .current) -> [CodingUsagePeriodRow] {
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        let month = calendar.dateInterval(of: .month, for: now)!

        return [
            CodingUsagePeriodRow(
                title: "Yesterday",
                counts: counts(in: DateInterval(start: yesterdayStart, end: todayStart))
            ),
            CodingUsagePeriodRow(
                title: "Today",
                counts: counts(in: DateInterval(start: todayStart, end: tomorrowStart))
            ),
            CodingUsagePeriodRow(title: "Weekly", counts: counts(in: week)),
            CodingUsagePeriodRow(title: "Monthly", counts: counts(in: month)),
        ]
    }

    func counts(in interval: DateInterval) -> CodingTokenCounts {
        dailyCounts.reduce(into: CodingTokenCounts()) { total, day in
            guard day.date >= interval.start && day.date < interval.end else {
                return
            }
            total.add(day.counts)
        }
    }

    func chartDays(endingAt date: Date, calendar: Calendar = .current) -> [CodingUsageDaySummary] {
        let dayCount = 30
        if !dailyCounts.isEmpty {
            return Array(dailyCounts.suffix(dayCount))
        }
        let today = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today)!

        return (0..<dayCount).map { offset in
            CodingUsageDaySummary(
                date: calendar.date(byAdding: .day, value: offset, to: start)!,
                counts: CodingTokenCounts()
            )
        }
    }
}

func formatCodingUsageCost(_ cost: Double) -> String {
    if cost <= 0 {
        return "$0.00"
    }
    if cost < 0.01 {
        return String(format: "$%.4f", cost)
    }
    return String(format: "$%.2f", cost)
}

func formatCodingUsageTokens(_ tokens: UInt64) -> String {
    let units: [(threshold: Double, suffix: String)] = [
        (1_000_000_000_000, "T"),
        (1_000_000_000, "B"),
        (1_000_000, "M"),
        (1_000, "K"),
    ]
    let value = Double(tokens)

    for unit in units {
        guard value >= unit.threshold else {
            continue
        }
        return String(format: "%.1f%@ tokens", value / unit.threshold, unit.suffix)
    }

    return String(format: "%.1f tokens", value)
}

struct CodingUsageReport: Equatable, Sendable {
    /// `nil` until the first load completes.
    let generatedAt: Date?
    let agents: [CodingUsageAgentSummary]

    var hasUsage: Bool {
        agents.contains { summary in
            summary.dailyCounts.contains { $0.counts.hasUsage }
        }
    }

    static var empty: Self {
        Self(
            generatedAt: nil,
            agents: CodingUsageAgent.allCases.map { agent in
                CodingUsageAgentSummary(agent: agent, dailyCounts: [])
            }
        )
    }
}

struct CodingUsageDateScope: Equatable, Sendable {
    let now: Date
    let history: DateInterval
    let historyDays: [Date]

    private let calendar: Calendar

    init(now: Date = .now, calendar: Calendar = .current) {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let rollingStart = calendar.date(byAdding: .day, value: -29, to: todayStart)!
        let monthStart = calendar.dateInterval(of: .month, for: now)!.start
        let historyStart = min(rollingStart, monthStart)
        let dayCount = calendar.dateComponents([.day], from: historyStart, to: tomorrowStart).day!

        self.now = now
        self.calendar = calendar
        self.history = DateInterval(start: historyStart, end: tomorrowStart)
        self.historyDays = (0..<dayCount).map {
            calendar.date(byAdding: .day, value: $0, to: historyStart)!
        }
    }

    func historyDay(containing date: Date) -> Date? {
        guard date >= history.start && date < history.end else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }
}
