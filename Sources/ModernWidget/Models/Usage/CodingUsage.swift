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

struct CodingTokenCounts: Hashable, Sendable {
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
        inputTokens = inputTokens.saturatingAdd(other.inputTokens)
        outputTokens = outputTokens.saturatingAdd(other.outputTokens)
        cacheCreationTokens = cacheCreationTokens.saturatingAdd(other.cacheCreationTokens)
        cacheReadTokens = cacheReadTokens.saturatingAdd(other.cacheReadTokens)
        reasoningTokens = reasoningTokens.saturatingAdd(other.reasoningTokens)
        totalTokens = totalTokens.saturatingAdd(other.totalTokens)
        costUSD += other.costUSD
    }
}

struct CodingUsageDaySummary: Equatable, Sendable {
    let date: Date
    let counts: CodingTokenCounts
}

struct CodingUsagePeriodRow: Equatable, Identifiable, Sendable {
    enum ID: Hashable, Sendable {
        case yesterday
        case today
        case weekly
        case monthly

        var title: String {
            switch self {
            case .yesterday:
                return "Yesterday"
            case .today:
                return "Today"
            case .weekly:
                return "Weekly"
            case .monthly:
                return "Monthly"
            }
        }
    }

    let id: ID
    let counts: CodingTokenCounts

    var title: String {
        id.title
    }
}

struct CodingUsageCostTrend: Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        case up
        case down
        case flat
    }

    let percent: Double

    var direction: Direction {
        if percent > 0 {
            return .up
        }
        if percent < 0 {
            return .down
        }
        return .flat
    }

    init(currentCostUSD: Double, previousCostUSD: Double) {
        let rawPercent: Double
        if previousCostUSD > 0 {
            rawPercent = (currentCostUSD - previousCostUSD) / previousCostUSD * 100
        } else {
            rawPercent = currentCostUSD > 0 ? 100 : 0
        }

        let rounded = (rawPercent * 10).rounded(.toNearestOrEven) / 10
        self.percent = rounded == 0 ? 0 : rounded
    }
}

struct CodingUsageTodaySummary: Equatable, Sendable {
    let date: Date
    let counts: CodingTokenCounts
    let costTrend: CodingUsageCostTrend
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
                id: .yesterday,
                counts: counts(in: DateInterval(start: yesterdayStart, end: todayStart))
            ),
            CodingUsagePeriodRow(
                id: .today,
                counts: counts(in: DateInterval(start: todayStart, end: tomorrowStart))
            ),
            CodingUsagePeriodRow(id: .weekly, counts: counts(in: week)),
            CodingUsagePeriodRow(id: .monthly, counts: counts(in: month)),
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

struct CodingUsageReport: Equatable, Sendable {
    /// `nil` until the first load completes.
    let generatedAt: Date?
    let agents: [CodingUsageAgentSummary]

    var hasUsage: Bool {
        agents.contains { summary in
            summary.dailyCounts.contains { $0.counts.hasUsage }
        }
    }

    func counts(in interval: DateInterval) -> CodingTokenCounts {
        agents.reduce(into: CodingTokenCounts()) { total, summary in
            total.add(summary.counts(in: interval))
        }
    }

    func todaySummary(now: Date, calendar: Calendar = .current) -> CodingUsageTodaySummary {
        let todayInterval = calendar.dateInterval(of: .day, for: now)!
        let todayStart = todayInterval.start
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let today = counts(in: todayInterval)
        let yesterday = counts(in: DateInterval(start: yesterdayStart, end: todayStart))

        return CodingUsageTodaySummary(
            date: todayStart,
            counts: today,
            costTrend: CodingUsageCostTrend(
                currentCostUSD: today.costUSD,
                previousCostUSD: yesterday.costUSD
            )
        )
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
