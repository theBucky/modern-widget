import Foundation
import Testing

@testable import ModernWidget

@Suite("Coding usage loader")
struct CodingUsageLoaderTests {
    @Test("loads claude usage for thirty day history")
    func loadsClaudeUsageForThirtyDayHistory() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-Claude")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            [
                #"{"timestamp":"2026-06-18T01:00:00.000Z","version":"1.2.3","sessionId":"session-a","requestId":"req-parent","message":{"id":"msg-parent","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":10,"cache_creation_input_tokens":5,"cache_read_input_tokens":20}}}"#,
                #"{"timestamp":"2026-06-18T01:01:00.000Z","version":"1.2.3","sessionId":"session-a","requestId":"req-sidechain","isSidechain":true,"message":{"id":"msg-parent","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":10,"cache_creation_input_tokens":5,"cache_read_input_tokens":50000}}}"#,
                #"{"timestamp":"2026-06-17T05:00:00.000Z","version":"1.2.3","sessionId":"session-a","requestId":"req-yesterday","message":{"id":"msg-yesterday","model":"claude-sonnet-4-20250514","usage":{"input_tokens":3,"output_tokens":7,"cache_creation":{"ephemeral_5m_input_tokens":2,"ephemeral_1h_input_tokens":4},"cache_read_input_tokens":1}}}"#,
            ].joined(separator: "\n"),
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.totalCounts.totalTokens == 152)
        #expect(abs(claude.totalCounts.costUSD - 0.00062055) < 0.00000001)
        #expect(claude.dailyCounts.count == 30)
        #expect(claude.dailyCounts.first?.date == date(2026, 5, 20))
        #expect(claude.dailyCounts.last?.date == date(2026, 6, 18))
        #expect(dayCounts(claude, 2026, 6, 18).totalTokens == 135)
        #expect(dayCounts(claude, 2026, 6, 17).totalTokens == 17)
        #expect(abs(dayCounts(claude, 2026, 6, 18).costUSD - 0.00047475) < 0.00000001)
        #expect(abs(dayCounts(claude, 2026, 6, 17).costUSD - 0.0001458) < 0.00000001)
    }

    @Test("loads codex usage from active sessions before archived duplicates")
    func loadsCodexUsageFromActiveSessionsBeforeArchivedDuplicates() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-Codex")
        defer { try? FileManager.default.removeItem(at: home) }

        let activeLog = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.2"}}"#,
            #"{"timestamp":"2026-06-18T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":125}}}}"#,
            #"{"timestamp":"2026-06-18T01:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":30,"output_tokens":35,"reasoning_output_tokens":10,"total_tokens":195}}}}"#,
            #"{"type":"turn.completed","timestamp":"2026-06-17T03:04:05.000Z","model":"gpt-5.2-codex","usage":{"prompt_tokens":11,"cached_tokens":1,"completion_tokens":9}}"#,
        ].joined(separator: "\n")
        let archivedLog =
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":999,"cached_input_tokens":99,"output_tokens":99,"reasoning_output_tokens":9,"total_tokens":1107},"model":"gpt-5.2"}}}"#

        try writeFixture(activeLog, to: ".codex/sessions/2026/06/session.jsonl", in: home)
        try writeFixture(
            archivedLog, to: ".codex/archived_sessions/2026/06/session.jsonl", in: home)

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.inputTokens == 130)
        #expect(codex.totalCounts.cacheReadTokens == 31)
        #expect(codex.totalCounts.outputTokens == 44)
        #expect(codex.totalCounts.reasoningTokens == 10)
        #expect(codex.totalCounts.totalTokens == 205)
        #expect(abs(codex.totalCounts.costUSD - 0.000848925) < 0.00000001)
        #expect(codex.dailyCounts.count == 30)
        #expect(dayCounts(codex, 2026, 6, 18).totalTokens == 185)
        #expect(dayCounts(codex, 2026, 6, 17).totalTokens == 20)
        #expect(abs(dayCounts(codex, 2026, 6, 18).costUSD - 0.00070525) < 0.00000001)
        #expect(abs(dayCounts(codex, 2026, 6, 17).costUSD - 0.000143675) < 0.00000001)
    }

    @Test("loads pi usage from assistant messages")
    func loadsPiUsageFromAssistantMessages() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-Pi")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            [
                #"{"type":"message","timestamp":"2026-06-18T01:00:00.000Z","message":{"role":"user","usage":{"input":999,"output":999}}}"#,
                #"{"type":"message","timestamp":"2026-06-18T01:02:03.000Z","message":{"role":"assistant","model":"gpt-5.4","usage":{"input":100,"output":50,"cacheRead":10,"cacheWrite":20,"totalTokens":180}}}"#,
                #"{"type":"message","timestamp":"2026-06-17T01:02:03.000Z","message":{"role":"assistant","model":"claude-sonnet-4-20250514","usage":{"totalTokens":333}}}"#,
            ].joined(separator: "\n"),
            to: ".pi/agent/sessions/project-a/prefix_session-a.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let pi = report.agents.first { $0.agent == .pi }!

        #expect(pi.totalCounts.inputTokens == 100)
        #expect(pi.totalCounts.outputTokens == 383)
        #expect(pi.totalCounts.cacheCreationTokens == 20)
        #expect(pi.totalCounts.cacheReadTokens == 10)
        #expect(pi.totalCounts.totalTokens == 513)
        #expect(abs(pi.totalCounts.costUSD - 0.0060475) < 0.00000001)
        #expect(dayCounts(pi, 2026, 6, 18).totalTokens == 180)
        #expect(dayCounts(pi, 2026, 6, 17).totalTokens == 333)
    }

    @Test("skips records outside the thirty day scan window")
    func skipsRecordsOutsideThirtyDayScanWindow() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ScanWindow")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"type":"turn.completed","timestamp":"2026-05-19T03:04:05.000Z","model":"gpt-5.2-codex","usage":{"input_tokens":40,"cached_input_tokens":5,"output_tokens":8,"total_tokens":48}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.totalTokens == 0)
        #expect(dayCounts(codex, 2026, 6, 18).totalTokens == 0)
    }

    @Test("calculates newer claude model pricing and fast multiplier")
    func calculatesNewerClaudeModelPricingAndFastMultiplier() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-NewClaudePricing")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            [
                #"{"timestamp":"2026-06-18T01:00:00.000Z","version":"1.2.3","sessionId":"session-a","requestId":"req-fable","message":{"id":"msg-fable","model":"claude-fable-5","usage":{"input_tokens":10,"output_tokens":2,"cache_creation_input_tokens":20,"cache_read_input_tokens":30}}}"#,
                #"{"timestamp":"2026-06-18T01:01:00.000Z","version":"1.2.3","sessionId":"session-a","requestId":"req-fast","message":{"id":"msg-fast","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":2,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"speed":"fast"}}}"#,
            ].joined(separator: "\n"),
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(abs(claude.totalCounts.costUSD - 0.00096) < 0.00000001)
    }

    @Test("does not price an unknown numeric model version as its base model")
    func doesNotPriceUnknownNumericModelVersionAsBaseModel() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-VersionBump")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","version":"1.2.3","sessionId":"session-a","requestId":"req-a","message":{"id":"msg-a","model":"claude-opus-4-1-20990101","usage":{"input_tokens":100,"output_tokens":10}}}"#,
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.totalCounts.totalTokens == 110)
        #expect(claude.totalCounts.costUSD == 0)
    }

    @Test("rejects an out-of-range token count instead of trapping")
    func rejectsOutOfRangeTokenCount() {
        let loader = CodingUsageLoader(
            environment: [:], homeDirectory: FileManager.default.temporaryDirectory)

        #expect(loader.unsignedInteger(NSNumber(value: Double(UInt64.max))) == nil)
        #expect(loader.unsignedInteger(NSNumber(value: 42)) == 42)
        #expect(loader.unsignedInteger(NSNumber(value: 1.5)) == nil)
    }

    @Test("parses common utc log timestamps")
    func parsesCommonUTCLogTimestamps() {
        let loader = CodingUsageLoader(
            environment: [:], homeDirectory: FileManager.default.temporaryDirectory)

        #expect(loader.parseTimestamp("2026-06-18T01:02:03Z") == date(2026, 6, 18, 1, 2, 3))
        #expect(loader.parseTimestamp("2026-06-18T01:02:03.000Z") == date(2026, 6, 18, 1, 2, 3))
        #expect(loader.parseTimestamp(" 2026-06-18T01:02:03.000Z\n") == date(2026, 6, 18, 1, 2, 3))
        #expect(
            loader.parseTimestamp("2026-06-18T01:02:03.250Z")?
                .timeIntervalSince(date(2026, 6, 18, 1, 2, 3)) == 0.25)
        #expect(loader.parseTimestamp("2026-06-18T09:02:03+08:00") == date(2026, 6, 18, 1, 2, 3))
    }

    @Test("keeps codex events with different fractional timestamps")
    func keepsCodexEventsWithDifferentFractionalTimestamps() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-CodexFractionalTimestamps")
        defer { try? FileManager.default.removeItem(at: home) }

        let log = [
            #"{"timestamp":"2026-06-18T01:00:00.001Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"model":"gpt-5.2"}}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.002Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"model":"gpt-5.2"}}}"#,
        ].joined(separator: "\n")
        try writeFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.totalTokens == 240)
    }

    @Test("loads repeated codex token count snapshots")
    func loadsRepeatedCodexTokenCountSnapshots() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-CodexSnapshots")
        defer { try? FileManager.default.removeItem(at: home) }

        let log = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.2"}}"#,
            #"{"timestamp":"2026-06-18T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":125},"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":125}}}}"#,
            #"{"timestamp":"2026-06-18T01:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":125},"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":125}}}}"#,
        ].joined(separator: "\n")
        try writeFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.totalTokens == 240)
    }

    @Test("uses fast codex pricing from config")
    func usesFastCodexPricingFromConfig() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-FastCodex")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(#"service_tier = "fast""#, to: ".codex/config.toml", in: home)
        try writeFixture(
            #"{"type":"turn.completed","timestamp":"2026-06-18T03:04:05.000Z","model":"gpt-5.5","usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":5,"total_tokens":105}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(abs(codex.totalCounts.costUSD - 0.001175) < 0.00000001)
    }

    @Test("ignores scoped codex service tier overrides")
    func ignoresScopedCodexServiceTierOverrides() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ScopedCodexTier")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            """
            [profiles.work]
            service_tier = "fast"
            """, to: ".codex/config.toml", in: home)
        try writeFixture(
            #"{"type":"turn.completed","timestamp":"2026-06-18T03:04:05.000Z","model":"gpt-5.5","usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":5,"total_tokens":105}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(abs(codex.totalCounts.costUSD - 0.00047) < 0.00000001)
    }

    @Test("prices codex roots with their own service tier")
    func pricesCodexRootsWithTheirOwnServiceTier() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-MixedCodexHome")
        let standardRoot = try makeFixtureRoot("CodingUsageLoaderTests-MixedCodexStandard")
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: standardRoot)
        }

        try writeFixture(#"service_tier = "fast""#, to: ".codex/config.toml", in: home)
        try writeFixture(
            #"{"type":"turn.completed","timestamp":"2026-06-18T03:04:05.000Z","model":"gpt-5.5","usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":5,"total_tokens":105}}"#,
            to: ".codex/sessions/fast.jsonl",
            in: home
        )
        try writeFixture(
            #"{"type":"turn.completed","timestamp":"2026-06-18T03:04:05.000Z","model":"gpt-5.5","usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":5,"total_tokens":105}}"#,
            to: ".codex/sessions/standard.jsonl",
            in: standardRoot
        )

        let codexHomes = [
            home.appendingPathComponent(".codex").path,
            standardRoot.appendingPathComponent(".codex").path,
        ].joined(separator: ",")
        let report = CodingUsageLoader(
            environment: ["CODEX_HOME": codexHomes],
            homeDirectory: home
        )
        .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(abs(codex.totalCounts.costUSD - 0.001645) < 0.00000001)
    }

    @Test("keeps the full current month in the scan window")
    func keepsFullCurrentMonthInScanWindow() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-FullMonth")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"timestamp":"2026-01-01T03:04:05.000Z","version":"1.2.3","sessionId":"session-a","requestId":"req-a","message":{"id":"msg-a","model":"claude-sonnet-4-20250514","usage":{"input_tokens":10,"output_tokens":1}}}"#,
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home,
            modifiedAt: date(2026, 1, 31, 12)
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(
                scope: CodingUsageDateScope(
                    now: date(2026, 1, 31, 12),
                    calendar: gregorianUTC(firstWeekday: 2)
                )
            )
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.dailyCounts.first?.date == date(2026, 1, 1))
        #expect(claude.dailyCounts.count == 31)
        #expect(dayCounts(claude, 2026, 1, 1).totalTokens == 11)
    }

    @Test("home scan only reads app data directories")
    func homeScanOnlyReadsAppDataDirectories() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-GrantHome")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","version":"1.2.3","sessionId":"bad","message":{"id":"bad","model":"claude-sonnet-4-20250514","usage":{"input_tokens":999,"output_tokens":999}}}"#,
            to: "projects/unrelated/chat.jsonl",
            in: home
        )
        try writeFixture(
            #"{"type":"turn.completed","timestamp":"2026-06-18T03:04:05.000Z","model":"gpt-5.2-codex","usage":{"input_tokens":999,"output_tokens":999}}"#,
            to: "random.jsonl",
            in: home
        )
        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","version":"1.2.3","sessionId":"session-a","message":{"id":"msg-a","model":"claude-sonnet-4-20250514","usage":{"input_tokens":10,"output_tokens":1}}}"#,
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )
        try writeFixture(
            #"{"type":"turn.completed","timestamp":"2026-06-18T03:04:05.000Z","model":"gpt-5.2-codex","usage":{"input_tokens":40,"cached_input_tokens":5,"output_tokens":8,"total_tokens":48}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(claude.totalCounts.totalTokens == 11)
        #expect(codex.totalCounts.totalTokens == 48)
    }

    @Test("skips stale files before parsing")
    func skipsStaleFilesBeforeParsing() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-StaleFiles")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","version":"1.2.3","sessionId":"session-a","message":{"id":"msg-a","model":"claude-sonnet-4-20250514","usage":{"input_tokens":999,"output_tokens":999}}}"#,
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home,
            modifiedAt: date(2026, 5, 1)
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.totalCounts.totalTokens == 0)
    }

    @Test("fingerprint changes when usage files change")
    func fingerprintChangesWhenUsageFilesChange() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-Fingerprint")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"type":"turn.completed","timestamp":"2026-06-18T03:04:05.000Z","model":"gpt-5.2-codex","usage":{"input_tokens":40,"output_tokens":8}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home
        )
        let loader = CodingUsageLoader(environment: [:], homeDirectory: home)
        let first = loader.usageScan(scope: scope()).fingerprint

        try writeFixture(
            #"{"type":"turn.completed","timestamp":"2026-06-18T03:04:05.000Z","model":"gpt-5.2-codex","usage":{"input_tokens":41,"output_tokens":8}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home,
            modifiedAt: date(2026, 6, 18, 12, 1)
        )

        #expect(loader.usageScan(scope: scope()).fingerprint != first)
    }

    @Test("reports no usage when no usage data is found")
    func reportsNoUsageWhenNoUsageDataIsFound() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-Empty")
        defer { try? FileManager.default.removeItem(at: home) }

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())

        #expect(!report.hasUsage)
    }

    private func scope() -> CodingUsageDateScope {
        CodingUsageDateScope(
            now: date(2026, 6, 18, 12),
            calendar: gregorianUTC(firstWeekday: 2)
        )
    }
}

private func makeFixtureRoot(_ name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "\(name).\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func writeFixture(_ text: String, to relativePath: String, in root: URL) throws {
    try writeFixture(text, to: relativePath, in: root, modifiedAt: date(2026, 6, 18, 12))
}

private func writeFixture(
    _ text: String,
    to relativePath: String,
    in root: URL,
    modifiedAt: Date
) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try text.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
}

private func dayCounts(
    _ summary: CodingUsageAgentSummary,
    _ year: Int,
    _ month: Int,
    _ day: Int
) -> CodingTokenCounts {
    summary.dailyCounts.first { $0.date == date(year, month, day) }?.counts ?? CodingTokenCounts()
}
