import Foundation

enum CodingUsageAgent: CaseIterable, Hashable, Sendable {
    case claude
    case codex
    case pi

    static func ordered(_ agents: Set<Self>) -> [Self] {
        allCases.filter { agents.contains($0) }
    }

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
}

struct CodingUsageDaySummary: Equatable, Sendable {
    let date: Date
    let counts: CodingTokenCounts
}

struct CodingUsagePeriodRow: Equatable, Identifiable, Sendable {
    let title: String
    let counts: CodingTokenCounts

    var id: String { title }
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
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: todayStart)!
        }

        return [
            ("Today", day(0), day(1)),
            ("Yesterday", day(-1), day(0)),
            ("Last 7 Days", day(-6), day(1)),
            ("Last 30 Days", day(-29), day(1)),
        ].map { title, start, end in
            CodingUsagePeriodRow(
                title: title, counts: counts(in: DateInterval(start: start, end: end)))
        }
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
        let dayCount = CodingUsageDateScope.historyDayCount
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
    enum State: Equatable, Sendable {
        case loading
        case loaded(generatedAt: Date)
    }

    let state: State
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

    func showingAgents(_ enabledAgents: Set<CodingUsageAgent>) -> Self {
        let summariesByAgent = Dictionary(uniqueKeysWithValues: agents.map { ($0.agent, $0) })

        return Self(
            state: state,
            agents: CodingUsageAgent.ordered(enabledAgents).map { agent in
                summariesByAgent[agent] ?? CodingUsageAgentSummary(agent: agent, dailyCounts: [])
            }
        )
    }

    static let empty = Self(
        state: .loading,
        agents: CodingUsageAgent.allCases.map { agent in
            CodingUsageAgentSummary(agent: agent, dailyCounts: [])
        }
    )
}
