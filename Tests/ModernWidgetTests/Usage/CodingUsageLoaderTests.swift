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

    @Test("filters claude usage before deduping duplicate messages")
    func filtersClaudeUsageBeforeDedupingDuplicateMessages() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ClaudeDedupeWindow")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            [
                #"{"timestamp":"2026-05-19T01:00:00.000Z","requestId":"req-a","message":{"id":"msg-a","model":"claude-sonnet-4-20250514","usage":{"input_tokens":999,"output_tokens":1}}}"#,
                #"{"timestamp":"2026-06-18T01:00:00.000Z","requestId":"req-a","message":{"id":"msg-a","model":"claude-sonnet-4-20250514","usage":{"input_tokens":10,"output_tokens":5}}}"#,
            ].joined(separator: "\n"),
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(dayCounts(claude, 2026, 6, 18).inputTokens == 10)
        #expect(dayCounts(claude, 2026, 6, 18).outputTokens == 5)
        #expect(claude.totalCounts.totalTokens == 15)
    }

    @Test("counts only claude records with timestamp, message, and usage")
    func countsOnlyClaudeRecordsWithTimestampMessageAndUsage() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ClaudeRequiredFields")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            [
                #"{"message":{"id":"msg-no-timestamp","model":"claude-sonnet-4-20250514","usage":{"input_tokens":50,"output_tokens":5}}}"#,
                #"{"timestamp":"2026-06-18T01:00:01.000Z","usage":{"input_tokens":60,"output_tokens":6}}"#,
                #"{"timestamp":"2026-06-18T01:00:02.000Z","message":{"id":"msg-no-usage","model":"claude-sonnet-4-20250514","note":"usage omitted"}}"#,
                #"{"timestamp":"2026-06-18T01:00:03.000Z","requestId":"req-ok","message":{"id":"msg-ok","model":"claude-sonnet-4-20250514","usage":{"input_tokens":10,"output_tokens":2}}}"#,
            ].joined(separator: "\n"),
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.totalCounts.inputTokens == 10)
        #expect(claude.totalCounts.outputTokens == 2)
        #expect(claude.totalCounts.totalTokens == 12)
    }

    @Test("prefers claude cache creation object over flat fallback")
    func prefersClaudeCacheCreationObjectOverFlatFallback() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ClaudeCacheObject")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","requestId":"req-a","message":{"id":"msg-a","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":20,"cache_creation_input_tokens":999,"cache_creation":{"ephemeral_5m_input_tokens":10,"ephemeral_1h_input_tokens":6},"cache_read_input_tokens":5}}}"#,
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.totalCounts.cacheCreationTokens == 16)
        #expect(claude.totalCounts.totalTokens == 141)
        #expect(abs(claude.totalCounts.costUSD - 0.000675) < 0.00000001)
    }

    @Test("prices flat claude cache creation as five minute only")
    func pricesFlatClaudeCacheCreationAsFiveMinuteOnly() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ClaudeFlatCache")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","requestId":"req-a","message":{"id":"msg-a","model":"claude-sonnet-4-20250514","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":40,"cache_read_input_tokens":0}}}"#,
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.totalCounts.cacheCreationTokens == 40)
        #expect(abs(claude.totalCounts.costUSD - 0.00015) < 0.00000001)
    }

    @Test("keeps non-sidechain claude record over sidechain duplicate")
    func keepsNonSidechainClaudeRecordOverSidechainDuplicate() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ClaudeNonSidechainWins")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            [
                #"{"timestamp":"2026-06-18T01:00:00.000Z","requestId":"req-main","message":{"id":"msg-z","model":"claude-sonnet-4-20250514","usage":{"input_tokens":10,"output_tokens":1}}}"#,
                #"{"timestamp":"2026-06-18T01:00:01.000Z","isSidechain":true,"requestId":"req-side","message":{"id":"msg-z","model":"claude-sonnet-4-20250514","usage":{"input_tokens":500,"output_tokens":50}}}"#,
            ].joined(separator: "\n"),
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.totalCounts.totalTokens == 11)
    }

    @Test("counts non-sidechain claude duplicates with different request ids")
    func countsNonSidechainClaudeDuplicatesWithDifferentRequestIds() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ClaudeNonSidechainDuplicates")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            [
                #"{"timestamp":"2026-06-18T01:00:00.000Z","requestId":"req-1","message":{"id":"msg-x","model":"claude-sonnet-4-20250514","usage":{"input_tokens":10,"output_tokens":1}}}"#,
                #"{"timestamp":"2026-06-18T01:00:01.000Z","requestId":"req-2","message":{"id":"msg-x","model":"claude-sonnet-4-20250514","usage":{"input_tokens":20,"output_tokens":2}}}"#,
            ].joined(separator: "\n"),
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.totalCounts.inputTokens == 30)
        #expect(claude.totalCounts.outputTokens == 3)
        #expect(claude.totalCounts.totalTokens == 33)
    }

    @Test("collapses equal-sidechain claude duplicates to the richer record")
    func collapsesEqualSidechainClaudeDuplicatesToTheRicherRecord() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ClaudeSidechainCollapse")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            [
                #"{"timestamp":"2026-06-18T01:00:00.000Z","isSidechain":true,"requestId":"req-1","message":{"id":"msg-y","model":"claude-sonnet-4-20250514","usage":{"input_tokens":10,"output_tokens":1}}}"#,
                #"{"timestamp":"2026-06-18T01:00:01.000Z","isSidechain":true,"requestId":"req-2","message":{"id":"msg-y","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":5}}}"#,
            ].joined(separator: "\n"),
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.totalCounts.totalTokens == 105)
    }

    @Test("uses claude speed not service tier for fast pricing")
    func usesClaudeSpeedNotServiceTierForFastPricing() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ClaudeFastDisposition")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            [
                #"{"timestamp":"2026-06-18T01:00:00.000Z","requestId":"req-tier","message":{"id":"msg-tier","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":2,"service_tier":"priority"}}}"#,
                #"{"timestamp":"2026-06-17T01:00:00.000Z","requestId":"req-speed","message":{"id":"msg-speed","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":2,"speed":"fast"}}}"#,
            ].joined(separator: "\n"),
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(abs(dayCounts(claude, 2026, 6, 18).costUSD - 0.0001) < 0.00000001)
        #expect(abs(dayCounts(claude, 2026, 6, 17).costUSD - 0.0002) < 0.00000001)
    }

    @Test("loads codex usage from active sessions before archived duplicates")
    func loadsCodexUsageFromActiveSessionsBeforeArchivedDuplicates() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-Codex")
        defer { try? FileManager.default.removeItem(at: home) }

        let activeLog = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.2"}}"#,
            #"{"timestamp":"2026-06-18T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":125}}}}"#,
            #"{"timestamp":"2026-06-18T01:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":30,"output_tokens":35,"reasoning_output_tokens":10,"total_tokens":195}}}}"#,
            #"{"timestamp":"2026-06-17T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":11,"cached_input_tokens":1,"output_tokens":9,"reasoning_output_tokens":0,"total_tokens":20},"model":"gpt-5.2-codex"}}}"#,
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

    @Test("dedupes identical codex events across differing active and archived paths")
    func dedupesCodexEventsAcrossDifferingPaths() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-CodexCrossPathDedupe")
        defer { try? FileManager.default.removeItem(at: home) }

        let event =
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5},"model":"gpt-5.2"}}}"#

        try writeFixture(event, to: ".codex/sessions/active/session.jsonl", in: home)
        try writeFixture(event, to: ".codex/archived_sessions/old/session.jsonl", in: home)

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.inputTokens == 90)
        #expect(codex.totalCounts.cacheReadTokens == 10)
        #expect(codex.totalCounts.outputTokens == 20)
        #expect(codex.totalCounts.reasoningTokens == 5)
        #expect(codex.totalCounts.totalTokens == 120)
    }

    @Test("skips codex subagent replayed parent token history")
    func skipsCodexSubagentReplayedParentTokenHistory() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-CodexSubagent")
        defer { try? FileManager.default.removeItem(at: home) }

        let log = [
            #"{"timestamp":"2026-06-18T00:59:59.000Z","type":"session_meta","payload":{"id":"subagent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":200,"reasoning_output_tokens":0,"total_tokens":1200}}}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.500Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1500,"cached_input_tokens":150,"output_tokens":300,"reasoning_output_tokens":0,"total_tokens":1800}}}}"#,
            #"{"timestamp":"2026-06-18T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1600,"cached_input_tokens":160,"output_tokens":320,"reasoning_output_tokens":0,"total_tokens":1920},"model":"gpt-5.2"}}}"#,
        ].joined(separator: "\n")
        try writeFixture(log, to: ".codex/sessions/subagent.jsonl", in: home)

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.inputTokens == 90)
        #expect(codex.totalCounts.cacheReadTokens == 10)
        #expect(codex.totalCounts.outputTokens == 20)
        #expect(codex.totalCounts.totalTokens == 120)
    }

    @Test("ignores codex thread spawn text outside subagent source")
    func ignoresCodexThreadSpawnTextOutsideSubagentSource() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-CodexThreadSpawnText")
        defer { try? FileManager.default.removeItem(at: home) }

        let log = [
            #"{"timestamp":"2026-06-18T00:59:59.000Z","type":"session_meta","payload":{"note":"thread_spawn copied from a transcript"}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":100},"model":"gpt-5.2"}}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.500Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":150},"model":"gpt-5.2"}}}"#,
        ].joined(separator: "\n")
        try writeFixture(log, to: ".codex/sessions/thread-spawn-text.jsonl", in: home)

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.inputTokens == 150)
        #expect(codex.totalCounts.totalTokens == 150)
    }

    @Test("keeps pending codex replay when another spawn appears")
    func keepsPendingCodexReplayWhenAnotherSpawnAppears() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-CodexPendingSpawn")
        defer { try? FileManager.default.removeItem(at: home) }

        let log = [
            #"{"timestamp":"2026-06-18T00:59:59.000Z","type":"session_meta","payload":{"source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent-a"}}}}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":100},"model":"gpt-5.2"}}}"#,
            #"{"timestamp":"2026-06-18T01:00:01.000Z","type":"session_meta","payload":{"source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent-b"}}}}}"#,
            #"{"timestamp":"2026-06-18T01:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":1000},"model":"gpt-5.2"}}}"#,
            #"{"timestamp":"2026-06-18T01:00:02.100Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1500,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":1500},"model":"gpt-5.2"}}}"#,
            #"{"timestamp":"2026-06-18T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1600,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":1600},"model":"gpt-5.2"}}}"#,
        ].joined(separator: "\n")
        try writeFixture(log, to: ".codex/sessions/pending-spawn.jsonl", in: home)

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.inputTokens == 200)
        #expect(codex.totalCounts.totalTokens == 200)
    }

    @Test("keeps suppressing codex replay when another spawn appears")
    func keepsSuppressingCodexReplayWhenAnotherSpawnAppears() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-CodexSuppressingSpawn")
        defer { try? FileManager.default.removeItem(at: home) }

        let log = [
            #"{"timestamp":"2026-06-18T00:59:59.000Z","type":"session_meta","payload":{"source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent-a"}}}}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":1000},"model":"gpt-5.2"}}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.100Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1500,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":1500},"model":"gpt-5.2"}}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.200Z","type":"session_meta","payload":{"source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent-b"}}}}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.300Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1600,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":1600},"model":"gpt-5.2"}}}"#,
            #"{"timestamp":"2026-06-18T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1700,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":1700},"model":"gpt-5.2"}}}"#,
        ].joined(separator: "\n")
        try writeFixture(log, to: ".codex/sessions/suppressing-spawn.jsonl", in: home)

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.inputTokens == 100)
        #expect(codex.totalCounts.totalTokens == 100)
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
                #"{"type":"message","timestamp":"2026-06-18T02:00:00.000Z","message":{"role":"assistant","model":"gpt-5.4","usage":{"input":100,"output":50,"cacheRead":10,"cacheWrite":20,"cacheWrite1h":8,"totalTokens":180}}}"#,
            ].joined(separator: "\n"),
            to: ".pi/agent/sessions/project-a/prefix_session-a.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let pi = report.agents.first { $0.agent == .pi }!

        #expect(pi.totalCounts.inputTokens == 200)
        #expect(pi.totalCounts.outputTokens == 433)
        #expect(pi.totalCounts.cacheCreationTokens == 40)
        #expect(pi.totalCounts.cacheReadTokens == 20)
        #expect(pi.totalCounts.totalTokens == 693)
        #expect(abs(pi.totalCounts.costUSD - 0.00712) < 0.00000001)
        #expect(dayCounts(pi, 2026, 6, 18).totalTokens == 360)
        #expect(dayCounts(pi, 2026, 6, 17).totalTokens == 333)
    }

    @Test("reads pi camelCase usage fields and ignores snake_case fields")
    func readsPiCamelCaseUsageFieldsIgnoringSnakeCase() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-PiCamelCase")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"type":"message","timestamp":"2026-06-18T01:00:00.000Z","message":{"role":"assistant","model":"gpt-5.4","usage":{"input_tokens":999,"output_tokens":999,"cache_read_input_tokens":999,"cache_creation_input_tokens":999,"input":100,"output":50,"cacheRead":10,"cacheWrite":20,"totalTokens":180}}}"#,
            to: ".pi/agent/sessions/project-a/prefix_session-a.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let pi = report.agents.first { $0.agent == .pi }!

        #expect(pi.totalCounts.inputTokens == 100)
        #expect(pi.totalCounts.outputTokens == 50)
        #expect(pi.totalCounts.cacheReadTokens == 10)
        #expect(pi.totalCounts.cacheCreationTokens == 20)
        #expect(pi.totalCounts.totalTokens == 180)
    }

    @Test("infers pi missing output but keeps explicit zero output")
    func infersPiMissingOutputButKeepsExplicitZeroOutput() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-PiOutput")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            [
                #"{"type":"message","timestamp":"2026-06-18T01:00:00.000Z","message":{"role":"assistant","model":"gpt-5.4","usage":{"input":100,"cacheRead":10,"cacheWrite":20,"totalTokens":180}}}"#,
                #"{"type":"message","timestamp":"2026-06-17T01:00:00.000Z","message":{"role":"assistant","model":"gpt-5.4","usage":{"input":100,"output":0,"cacheRead":10,"cacheWrite":20,"totalTokens":180}}}"#,
            ].joined(separator: "\n"),
            to: ".pi/agent/sessions/project-a/prefix_session-a.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let pi = report.agents.first { $0.agent == .pi }!

        #expect(dayCounts(pi, 2026, 6, 18).outputTokens == 50)
        #expect(dayCounts(pi, 2026, 6, 18).totalTokens == 180)
        #expect(dayCounts(pi, 2026, 6, 17).outputTokens == 0)
        #expect(dayCounts(pi, 2026, 6, 17).totalTokens == 180)
        #expect(pi.totalCounts.outputTokens == 50)
    }

    @Test("clamps pi cacheWrite1h to cacheWrite without underflow")
    func clampsPiCacheWrite1hToCacheWrite() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-PiCacheWrite1h")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"type":"message","timestamp":"2026-06-18T01:00:00.000Z","message":{"role":"assistant","model":"gpt-5.4","usage":{"input":10,"output":20,"cacheWrite":20,"cacheWrite1h":50,"totalTokens":50}}}"#,
            to: ".pi/agent/sessions/project-a/prefix_session-a.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let pi = report.agents.first { $0.agent == .pi }!

        #expect(pi.totalCounts.cacheCreationTokens == 20)
        #expect(pi.totalCounts.totalTokens == 50)
        #expect(abs(pi.totalCounts.costUSD - 0.000425) < 0.00000001)
    }

    @Test("saturates malformed token totals")
    func saturatesMalformedTokenTotals() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-TokenOverflow")
        defer { try? FileManager.default.removeItem(at: home) }

        let max = UInt64.max
        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","message":{"id":"msg-overflow","model":"claude-sonnet-4-20250514","usage":{"input_tokens":\#(max),"output_tokens":1}}}"#,
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )
        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(max),"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0},"model":"gpt-5.2"}}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home
        )
        try writeFixture(
            #"{"type":"message","timestamp":"2026-06-18T01:00:00.000Z","message":{"role":"assistant","model":"gpt-5.4","usage":{"input":\#(max),"output":1}}}"#,
            to: ".pi/agent/sessions/project-a/prefix_session-a.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())

        #expect(report.agents.first { $0.agent == .claude }?.totalCounts.totalTokens == max)
        #expect(report.agents.first { $0.agent == .codex }?.totalCounts.totalTokens == max)
        #expect(report.agents.first { $0.agent == .pi }?.totalCounts.totalTokens == max)
    }

    @Test("skips escaped strings and nested content while extracting usage")
    func skipsEscapedContentWhileExtractingUsage() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-Escaped")
        defer { try? FileManager.default.removeItem(at: home) }

        // The content array carries escaped quotes, braces, and a backslash run that the
        // scanner must step over before reaching the trailing usage object.
        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","isSidechain":false,"requestId":"req-a","message":{"id":"msg-a","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"a \"quoted\" {brace} and trailing slash \\"}],"usage":{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":20}}}"#,
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(dayCounts(claude, 2026, 6, 18).inputTokens == 100)
        #expect(dayCounts(claude, 2026, 6, 18).outputTokens == 10)
        #expect(dayCounts(claude, 2026, 6, 18).cacheReadTokens == 20)
        #expect(dayCounts(claude, 2026, 6, 18).totalTokens == 130)
    }

    @Test("skips records outside the thirty day scan window")
    func skipsRecordsOutsideThirtyDayScanWindow() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ScanWindow")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"timestamp":"2026-05-19T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":40,"cached_input_tokens":5,"output_tokens":8,"reasoning_output_tokens":0,"total_tokens":48},"model":"gpt-5.2-codex"}}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.totalTokens == 0)
        #expect(dayCounts(codex, 2026, 6, 18).totalTokens == 0)
    }

    @Test("normalizes codex cache tokens before pricing")
    func normalizesCodexCacheTokensBeforePricing() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-CodexCacheClamp")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"timestamp":"2026-06-18T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":20,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":15},"model":"gpt-5.2"}}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.inputTokens == 0)
        #expect(codex.totalCounts.cacheReadTokens == 10)
        #expect(codex.totalCounts.outputTokens == 5)
        #expect(codex.totalCounts.totalTokens == 15)
        #expect(abs(codex.totalCounts.costUSD - 0.00007175) < 0.00000001)
    }

    @Test("ignores malformed token counts without failing the load")
    func ignoresMalformedTokenCountsWithoutFailingLoad() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-MalformedTokenCount")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","version":"1.2.3","sessionId":"session-a","requestId":"req-a","message":{"id":"msg-a","model":"claude-sonnet-4-20250514","usage":{"input_tokens":18446744073709551616,"output_tokens":7,"cache_creation_input_tokens":-1,"cache_read_input_tokens":1.5}}}"#,
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.totalCounts.inputTokens == 0)
        #expect(claude.totalCounts.outputTokens == 7)
        #expect(claude.totalCounts.cacheCreationTokens == 0)
        #expect(claude.totalCounts.cacheReadTokens == 0)
        #expect(claude.totalCounts.totalTokens == 7)
    }

    @Test("skips malformed numeric fields of every json type without dropping later fields")
    func skipsMalformedNumericFieldsOfEveryJSONType() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-MalformedFieldTypes")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            [
                #"{"timestamp":"2026-06-18T01:00:00.000Z","requestId":"req-string","message":{"id":"msg-string","model":"claude-sonnet-4-20250514","usage":{"input_tokens":"oops","output_tokens":1}}}"#,
                #"{"timestamp":"2026-06-18T01:00:01.000Z","requestId":"req-null","message":{"id":"msg-null","model":"claude-sonnet-4-20250514","usage":{"input_tokens":null,"output_tokens":2}}}"#,
                #"{"timestamp":"2026-06-18T01:00:02.000Z","requestId":"req-bool","message":{"id":"msg-bool","model":"claude-sonnet-4-20250514","usage":{"input_tokens":true,"output_tokens":4}}}"#,
                #"{"timestamp":"2026-06-18T01:00:03.000Z","requestId":"req-object","message":{"id":"msg-object","model":"claude-sonnet-4-20250514","usage":{"input_tokens":{"nested":99},"output_tokens":8}}}"#,
                #"{"timestamp":"2026-06-18T01:00:04.000Z","requestId":"req-array","message":{"id":"msg-array","model":"claude-sonnet-4-20250514","usage":{"input_tokens":[1,2,3],"output_tokens":16}}}"#,
            ].joined(separator: "\n"),
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let claude = report.agents.first { $0.agent == .claude }!

        #expect(claude.totalCounts.inputTokens == 0)
        #expect(claude.totalCounts.outputTokens == 31)
        #expect(claude.totalCounts.totalTokens == 31)
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

    @Test("parses common utc log timestamps")
    func parsesCommonUTCLogTimestamps() {
        #expect(LogTimestamp.parse("2026-06-18T01:02:03Z") == date(2026, 6, 18, 1, 2, 3))
        #expect(LogTimestamp.parse("2026-06-18T01:02:03.000Z") == date(2026, 6, 18, 1, 2, 3))
        #expect(
            LogTimestamp.parse("2026-06-18T01:02:03.250Z")?
                .timeIntervalSince(date(2026, 6, 18, 1, 2, 3)) == 0.25)
        #expect(LogTimestamp.parse(" 2026-06-18T01:02:03.000Z\n") == nil)
        #expect(LogTimestamp.parse("2026-06-18T09:02:03+08:00") == nil)
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
            #"{"timestamp":"2026-06-18T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":125}}}}"#,
            #"{"timestamp":"2026-06-18T01:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":125}}}}"#,
        ].joined(separator: "\n")
        try writeFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.totalTokens == 240)
    }

    @Test("resolves codex model context from payload, info, turn context, and fallback")
    func resolvesCodexModelContextFromAllSources() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-CodexModelContext")
        defer { try? FileManager.default.removeItem(at: home) }

        let log = [
            #"{"timestamp":"2026-06-17T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":400,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":400}}}}"#,
            #"{"timestamp":"2026-06-14T01:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-06-14T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":100}}}}"#,
            #"{"timestamp":"2026-06-15T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"model":"gpt-5.2","last_token_usage":{"input_tokens":200,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":200}}}}"#,
            #"{"timestamp":"2026-06-16T01:00:00.000Z","type":"event_msg","payload":{"model":"gpt-5.5","type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":300}}}}"#,
        ].joined(separator: "\n")
        try writeFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let report = CodingUsageLoader(environment: [:], homeDirectory: home)
            .loadReport(scope: scope())
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(codex.totalCounts.totalTokens == 1000)
        #expect(abs(dayCounts(codex, 2026, 6, 17).costUSD - 0.0005) < 0.00000001)
        #expect(abs(dayCounts(codex, 2026, 6, 14).costUSD - 0.00025) < 0.00000001)
        #expect(abs(dayCounts(codex, 2026, 6, 15).costUSD - 0.00035) < 0.00000001)
        #expect(abs(dayCounts(codex, 2026, 6, 16).costUSD - 0.0015) < 0.00000001)
    }

    @Test("uses fast codex pricing from config")
    func usesFastCodexPricingFromConfig() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-FastCodex")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(#"service_tier = "fast""#, to: ".codex/config.toml", in: home)
        try writeFixture(
            #"{"timestamp":"2026-06-18T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":105},"model":"gpt-5.5"}}}"#,
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
            #"{"timestamp":"2026-06-18T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":105},"model":"gpt-5.5"}}}"#,
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
            #"{"timestamp":"2026-06-18T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":105},"model":"gpt-5.5"}}}"#,
            to: ".codex/sessions/fast.jsonl",
            in: home
        )
        try writeFixture(
            #"{"timestamp":"2026-06-18T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":105},"model":"gpt-5.5"}}}"#,
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

    @Test("empty directory overrides fall back to defaults")
    func emptyDirectoryOverridesFallBackToDefaults() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-EmptyDirectoryOverride")
        let customHome = try makeFixtureRoot("CodingUsageLoaderTests-CustomDirectoryOverride")
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: customHome)
        }

        let defaultLoader = CodingUsageLoader(
            environment: ["CODEX_HOME": " ,\n, \t"],
            homeDirectory: home
        )
        #expect(
            defaultLoader.codexHomeDirectories()
                == [home.appendingPathComponent(".codex").standardizedFileURL])

        let customLoader = CodingUsageLoader(
            environment: ["CODEX_HOME": " , \(customHome.path) ,\n"],
            homeDirectory: home
        )
        #expect(customLoader.codexHomeDirectories() == [customHome.standardizedFileURL])
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
            #"{"timestamp":"2026-06-18T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":999,"cached_input_tokens":0,"output_tokens":999,"reasoning_output_tokens":0,"total_tokens":1998},"model":"gpt-5.2-codex"}}}"#,
            to: "random.jsonl",
            in: home
        )
        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","version":"1.2.3","sessionId":"session-a","message":{"id":"msg-a","model":"claude-sonnet-4-20250514","usage":{"input_tokens":10,"output_tokens":1}}}"#,
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )
        try writeFixture(
            #"{"timestamp":"2026-06-18T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":40,"cached_input_tokens":5,"output_tokens":8,"reasoning_output_tokens":0,"total_tokens":48},"model":"gpt-5.2-codex"}}}"#,
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
            #"{"timestamp":"2026-06-18T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":40,"cached_input_tokens":0,"output_tokens":8,"reasoning_output_tokens":0,"total_tokens":48},"model":"gpt-5.2-codex"}}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home
        )
        let loader = CodingUsageLoader(environment: [:], homeDirectory: home)
        let first = loader.usageScan(scope: scope()).fingerprint

        try writeFixture(
            #"{"timestamp":"2026-06-18T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":41,"cached_input_tokens":0,"output_tokens":8,"reasoning_output_tokens":0,"total_tokens":49},"model":"gpt-5.2-codex"}}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home,
            modifiedAt: date(2026, 6, 18, 12, 1)
        )

        #expect(loader.usageScan(scope: scope()).fingerprint != first)
    }

    @Test("fingerprint changes when codex config pricing changes")
    func fingerprintChangesWhenCodexConfigChanges() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-ConfigFingerprint")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"timestamp":"2026-06-18T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":40,"cached_input_tokens":0,"output_tokens":8,"reasoning_output_tokens":0,"total_tokens":48},"model":"gpt-5.2-codex"}}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home
        )
        try writeFixture(#"service_tier = "standard""#, to: ".codex/config.toml", in: home)
        let loader = CodingUsageLoader(environment: [:], homeDirectory: home)
        let first = loader.usageScan(scope: scope()).fingerprint

        try writeFixture(
            #"service_tier = "fast""#,
            to: ".codex/config.toml",
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

    @Test("skips disabled usage agents before scanning")
    func skipsDisabledUsageAgentsBeforeScanning() throws {
        let home = try makeFixtureRoot("CodingUsageLoaderTests-DisabledAgents")
        defer { try? FileManager.default.removeItem(at: home) }

        try writeFixture(
            #"{"timestamp":"2026-06-18T01:00:00.000Z","message":{"id":"msg-a","model":"claude-sonnet-4-20250514","usage":{"input_tokens":10,"output_tokens":5}}}"#,
            to: ".claude/projects/project-a/session-a/chat.jsonl",
            in: home
        )
        try writeFixture(
            #"{"timestamp":"2026-06-18T03:04:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":40,"cached_input_tokens":0,"output_tokens":8,"reasoning_output_tokens":0,"total_tokens":48},"model":"gpt-5.2-codex"}}}"#,
            to: ".codex/sessions/session.jsonl",
            in: home
        )

        let loader = CodingUsageLoader(environment: [:], homeDirectory: home)
        let scan = loader.usageScan(scope: scope(), enabledAgents: [.codex])
        let report = loader.loadReport(scan: scan)
        let codex = report.agents.first { $0.agent == .codex }!

        #expect(scan.claudeFiles.isEmpty)
        #expect(scan.codexSources.flatMap(\.files).count == 1)
        #expect(report.agents.map(\.agent) == [.codex])
        #expect(codex.totalCounts.totalTokens == 48)
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
