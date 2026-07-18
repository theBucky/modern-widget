import Foundation
import Testing

@testable import ModernWidget

@Suite("Codex usage loader")
struct CodexUsageLoaderTests {
    @Test("prices every OpenAI model family in the catalog")
    func pricesSupportedModelFamilies() throws {
        let cases: [(model: String, inputCost: Double)] = [
            ("gpt-5.3-codex", 1.75),
            ("gpt-5.4", 2.5),
            ("gpt-5.4-mini", 0.75),
            ("gpt-5.4-nano", 0.2),
            ("gpt-5.5", 5),
            ("gpt-5.6-sol", 5),
            ("gpt-5.6-terra", 2.5),
            ("gpt-5.6-luna", 1),
        ]

        for expectation in cases {
            let home = try makeFixtureRoot("CodexUsagePricing-\(expectation.model)")
            defer { try? FileManager.default.removeItem(at: home) }
            let log = [
                turnContext(
                    at: "2026-06-18T00:59:59.000Z",
                    id: "turn-1",
                    model: expectation.model
                ),
                tokenCount(at: "2026-06-18T01:00:00.000Z", input: 100_000, cached: 0, output: 0),
            ].joined(separator: "\n")
            try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

            let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

            #expect(
                abs(totals.costUSD - expectation.inputCost / 10) < 0.000_001,
                "unexpected input price for \(expectation.model)"
            )
        }
    }

    @Test("derives requests from cumulative usage and ignores repeated totals")
    func derivesCumulativeDeltas() throws {
        let home = try makeFixtureRoot("CodexUsageCumulative")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}"#,
            tokenCount(at: "2026-06-18T01:01:00.000Z", input: 100, cached: 10, output: 20),
            tokenCount(at: "2026-06-18T01:01:30.000Z", input: 100, cached: 10, output: 20),
            tokenCount(at: "2026-06-18T01:02:00.000Z", input: 150, cached: 30, output: 35),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 185)
        #expect(abs(totals.costUSD - 0.000_705_25) < 0.000_000_001)
    }

    @Test("uses per-request usage when a cumulative snapshot is absent")
    func fallsBackToLastUsage() throws {
        let home = try makeFixtureRoot("CodexUsageLastUsage")
        defer { try? FileManager.default.removeItem(at: home) }
        let line =
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120}}}}"#
        let log = [
            #"{"timestamp":"2026-06-18T00:59:00.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}"#,
            line,
            line.replacingOccurrences(of: "01:00:00", with: "01:01:00"),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 240)
        #expect(abs(totals.costUSD - 0.000_878_5) < 0.000_000_001)
    }

    @Test("advances cumulative accounting after per-request fallback")
    func advancesCumulativeAccountingAfterFallback() throws {
        let home = try makeFixtureRoot("CodexUsageMixedCumulativeFallback")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T00:59:00.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}"#,
            tokenCount(at: "2026-06-18T01:00:00.000Z", input: 100, cached: 0, output: 0),
            #"{"timestamp":"2026-06-18T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":0}}}}"#,
            tokenCount(at: "2026-06-18T01:02:00.000Z", input: 120, cached: 0, output: 0),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 120)
    }

    @Test("resumes cumulative accounting after a context reset")
    func resumesAfterCumulativeReset() throws {
        let home = try makeFixtureRoot("CodexUsageCumulativeReset")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T00:59:00.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}"#,
            tokenCount(at: "2026-06-18T01:00:00.000Z", input: 100, cached: 10, output: 20),
            tokenCount(at: "2026-06-18T01:01:00.000Z", input: 0, cached: 0, output: 0),
            tokenCount(at: "2026-06-18T01:02:00.000Z", input: 40, cached: 0, output: 10),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 170)
    }

    @Test("prices cached input as a subset of total input")
    func pricesCachedInput() throws {
        let home = try makeFixtureRoot("CodexUsageCachedInput")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.5"}}"#,
            tokenCount(at: "2026-06-18T01:01:00.000Z", input: 1_000, cached: 400, output: 200),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 1_200)
        #expect(abs(totals.costUSD - 0.0092) < 0.000_000_1)
    }

    @Test("prices persisted cache writes at the cache write rate")
    func pricesCacheWrites() throws {
        let home = try makeFixtureRoot("CodexUsageCacheWrites")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}"#,
            tokenCount(
                at: "2026-06-18T01:01:00.000Z",
                input: 1_000,
                cached: 400,
                output: 200,
                cacheWrite: 100
            ),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 1_200)
        #expect(abs(totals.costUSD - 0.009_325) < 0.000_000_1)
    }

    @Test("applies long-context pricing to one request")
    func pricesLongContextPerRequest() throws {
        let home = try makeFixtureRoot("CodexUsageLongContext")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.5"}}"#,
            tokenCount(
                at: "2026-06-18T01:01:00.000Z",
                input: 300_000,
                cached: 100_000,
                output: 10_000
            ),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 310_000)
        #expect(abs(totals.costUSD - 2.55) < 0.000_001)
    }

    @Test("omits records without a known model")
    func omitsUnpriceableRecords() throws {
        let home = try makeFixtureRoot("CodexUsageUnknownModel")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            tokenCount(at: "2026-06-18T01:00:00.000Z", input: 100, cached: 0, output: 20),
            #"{"timestamp":"2026-06-18T01:01:00.000Z","type":"turn_context","payload":{"model":"gpt-5.99"}}"#,
            tokenCount(at: "2026-06-18T01:02:00.000Z", input: 200, cached: 0, output: 40),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(!totals.hasUsage)
    }

    @Test("suppresses every inherited snapshot without suppressing a fast child turn")
    func suppressesForkReplay() throws {
        let home = try makeFixtureRoot("CodexUsageForkReplay")
        defer { try? FileManager.default.removeItem(at: home) }
        let parent = [
            #"{"timestamp":"2026-06-18T00:59:00.000Z","type":"session_meta","payload":{"id":"origin"}}"#,
            turnContext(
                at: "2026-06-18T00:59:00.100Z",
                id: "origin-turn-1",
                model: "unsupported"
            ),
            tokenCount(at: "2026-06-18T00:59:01.000Z", input: 400, cached: 40, output: 80),
            turnContext(
                at: "2026-06-18T00:59:30.000Z",
                id: "origin-turn-2",
                model: "unsupported"
            ),
            tokenCount(at: "2026-06-18T00:59:31.000Z", input: 1_000, cached: 100, output: 200),
        ].joined(separator: "\n")
        let child = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"session_meta","payload":{"id":"fork","forked_from_id":"origin"}}"#,
            turnContext(
                at: "2026-06-18T01:00:00.010Z",
                id: "origin-turn-1",
                model: "unsupported"
            ),
            tokenCount(at: "2026-06-18T01:00:00.020Z", input: 400, cached: 40, output: 80),
            turnContext(
                at: "2026-06-18T01:00:00.030Z",
                id: "origin-turn-2",
                model: "unsupported"
            ),
            tokenCount(at: "2026-06-18T01:00:00.040Z", input: 1_000, cached: 100, output: 200),
            turnContext(
                at: "2026-06-18T01:00:00.100Z",
                id: "fork-turn",
                model: "gpt-5.3-codex"
            ),
            tokenCount(
                at: "2026-06-18T01:00:00.200Z",
                input: 1_600,
                cached: 160,
                output: 320
            ),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(parent, to: ".codex/sessions/origin.jsonl", in: home)
        try writeCodingUsageFixture(child, to: ".codex/sessions/fork.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 720)
    }

    @Test("suppresses inherited history identified by structured subagent metadata")
    func suppressesStructuredSubagentReplay() throws {
        let home = try makeFixtureRoot("CodexUsageSubagentReplay")
        defer { try? FileManager.default.removeItem(at: home) }
        let parent = [
            #"{"timestamp":"2026-06-18T00:59:00.000Z","type":"session_meta","payload":{"id":"parent"}}"#,
            turnContext(
                at: "2026-06-18T00:59:00.100Z",
                id: "parent-turn-1",
                model: "unsupported"
            ),
            tokenCount(at: "2026-06-18T00:59:01.000Z", input: 400, cached: 40, output: 80),
            turnContext(
                at: "2026-06-18T00:59:30.000Z",
                id: "parent-turn-2",
                model: "unsupported"
            ),
            tokenCount(at: "2026-06-18T00:59:31.000Z", input: 1_000, cached: 100, output: 200),
        ].joined(separator: "\n")
        let child = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"session_meta","payload":{"id":"child","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}}}"#,
            tokenCount(at: "2026-06-18T01:00:00.020Z", input: 1_000, cached: 100, output: 200),
            turnContext(
                at: "2026-06-18T01:00:00.100Z",
                id: "child-turn",
                model: "gpt-5.3-codex"
            ),
            tokenCount(
                at: "2026-06-18T01:00:00.200Z",
                input: 1_600,
                cached: 160,
                output: 320
            ),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(parent, to: ".codex/sessions/parent.jsonl", in: home)
        try writeCodingUsageFixture(child, to: ".codex/sessions/subagent.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 720)
    }

    @Test("resolves fork parents with a scalar session source")
    func resolvesScalarSessionSource() throws {
        let home = try makeFixtureRoot("CodexUsageScalarSessionSource")
        defer { try? FileManager.default.removeItem(at: home) }
        let parent = [
            #"{"timestamp":"2026-06-18T00:59:00.000Z","type":"session_meta","payload":{"id":"parent","source":"cli"}}"#,
            turnContext(
                at: "2026-06-18T00:59:00.100Z",
                id: "shared-turn",
                model: "unsupported"
            ),
            tokenCount(at: "2026-06-18T00:59:01.000Z", input: 100, cached: 0, output: 20),
        ].joined(separator: "\n")
        let child = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"session_meta","payload":{"id":"child","forked_from_id":"parent"}}"#,
            turnContext(
                at: "2026-06-18T01:00:00.010Z",
                id: "shared-turn",
                model: "unsupported"
            ),
            tokenCount(at: "2026-06-18T01:00:00.020Z", input: 100, cached: 0, output: 20),
            turnContext(
                at: "2026-06-18T01:00:00.100Z",
                id: "child-turn",
                model: "gpt-5.3-codex"
            ),
            tokenCount(at: "2026-06-18T01:00:00.200Z", input: 200, cached: 0, output: 40),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(parent, to: ".codex/sessions/parent.jsonl", in: home)
        try writeCodingUsageFixture(child, to: ".codex/sessions/child.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 120)
    }

    @Test("resolves fork parents outside the history window")
    func resolvesStaleForkParent() throws {
        let home = try makeFixtureRoot("CodexUsageStaleForkParent")
        defer { try? FileManager.default.removeItem(at: home) }
        let parentID = "00000000-0000-0000-0000-000000000001"
        let parent = [
            #"{"timestamp":"2026-05-01T00:59:00.000Z","type":"session_meta","payload":{"id":"\#(parentID)"}}"#,
            turnContext(
                at: "2026-05-01T00:59:00.100Z",
                id: "shared-turn",
                model: "unsupported"
            ),
            tokenCount(at: "2026-05-01T00:59:01.000Z", input: 100, cached: 0, output: 20),
        ].joined(separator: "\n")
        let child = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"session_meta","payload":{"id":"child","forked_from_id":"\#(parentID)"}}"#,
            turnContext(
                at: "2026-06-18T01:00:00.010Z",
                id: "shared-turn",
                model: "unsupported"
            ),
            tokenCount(at: "2026-06-18T01:00:00.020Z", input: 100, cached: 0, output: 20),
            turnContext(
                at: "2026-06-18T01:00:00.100Z",
                id: "child-turn",
                model: "gpt-5.3-codex"
            ),
            tokenCount(at: "2026-06-18T01:00:00.200Z", input: 200, cached: 0, output: 40),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(
            parent,
            to: ".codex/sessions/2026/05/01/rollout-2026-05-01T00-59-00-\(parentID).jsonl",
            in: home,
            modifiedAt: date(2026, 5, 1)
        )
        try writeCodingUsageFixture(
            child,
            to: ".codex/sessions/2026/06/18/child.jsonl",
            in: home
        )

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 120)
    }

    @Test("inherits the model from a replayed fork turn context")
    func inheritsForkReplayModel() throws {
        let home = try makeFixtureRoot("CodexUsageForkReplayModel")
        defer { try? FileManager.default.removeItem(at: home) }
        let parent = [
            #"{"timestamp":"2026-06-18T00:59:00.000Z","type":"session_meta","payload":{"id":"parent"}}"#,
            turnContext(
                at: "2026-06-18T00:59:00.100Z",
                id: "shared-turn",
                model: "gpt-5.3-codex"
            ),
            tokenCount(at: "2026-06-18T00:59:01.000Z", input: 100, cached: 0, output: 20),
        ].joined(separator: "\n")
        let child = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"session_meta","payload":{"id":"child","forked_from_id":"parent"}}"#,
            turnContext(
                at: "2026-06-18T01:00:00.010Z",
                id: "shared-turn",
                model: "gpt-5.3-codex"
            ),
            tokenCount(at: "2026-06-18T01:00:00.020Z", input: 100, cached: 0, output: 20),
            tokenCount(at: "2026-06-18T01:00:00.200Z", input: 200, cached: 0, output: 40),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(parent, to: ".codex/sessions/parent.jsonl", in: home)
        try writeCodingUsageFixture(child, to: ".codex/sessions/child.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 240)
    }

    @Test("active sessions take precedence over archived copies")
    func activeSessionsTakePrecedence() throws {
        let home = try makeFixtureRoot("CodexUsageArchiveDedupe")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            turnContext(at: "2026-06-18T00:59:00.000Z", id: "turn-1", model: "gpt-5.3-codex"),
            tokenCount(at: "2026-06-18T01:00:00.000Z", input: 100, cached: 0, output: 20),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/day/session.jsonl", in: home)
        try writeCodingUsageFixture(
            log,
            to: ".codex/archived_sessions/day/session.jsonl",
            in: home
        )

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 120)
    }

    @Test("counts identical usage emitted by independent sessions")
    func countsIndependentIdenticalRecords() throws {
        let home = try makeFixtureRoot("CodexUsageIndependentSessions")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            turnContext(at: "2026-06-18T00:59:00.000Z", id: "turn-1", model: "gpt-5.3-codex"),
            tokenCount(at: "2026-06-18T01:00:00.000Z", input: 100, cached: 0, output: 20),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/a.jsonl", in: home)
        try writeCodingUsageFixture(log, to: ".codex/sessions/b.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 240)
    }

    @Test("prices usage that follows an empty cumulative snapshot")
    func pricesUsageAfterEmptySnapshot() throws {
        let home = try makeFixtureRoot("CodexUsageEmptySnapshot")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            turnContext(at: "2026-06-18T00:59:00.000Z", id: "turn-1", model: "gpt-5.3-codex"),
            tokenCount(at: "2026-06-18T01:00:00.000Z", input: 0, cached: 0, output: 0),
            tokenCount(at: "2026-06-18T01:01:00.000Z", input: 100, cached: 0, output: 20),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 120)
    }

    @Test("rejects malformed or incomplete token fields")
    func rejectsMalformedUsage() throws {
        let home = try makeFixtureRoot("CodexUsageMalformed")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T00:59:00.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":"100","cached_input_tokens":0,"output_tokens":20}}}}"#,
            #"{"timestamp":"2026-06-18T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":20}}}}"#,
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(!totals.hasUsage)
    }

    @Test("rejects malformed structure outside consumed fields")
    func rejectsMalformedDocumentStructure() throws {
        let home = try makeFixtureRoot("CodexUsageMalformedStructure")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T00:59:00.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20}},"extra":}}"#,
            #"{"timestamp":"2026-06-18T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20}},"extra":{"nested":1]}}"#,
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(!totals.hasUsage)
    }
}

private func tokenCount(
    at timestamp: String,
    input: UInt64,
    cached: UInt64,
    output: UInt64,
    cacheWrite: UInt64? = nil
) -> String {
    let cacheWriteField = cacheWrite.map { #","cache_write_input_tokens":\#($0)"# } ?? ""
    return
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached)\#(cacheWriteField),"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(input + output)}}}}"#
}

private func turnContext(at timestamp: String, id: String, model: String) -> String {
    #"{"timestamp":"\#(timestamp)","type":"turn_context","payload":{"turn_id":"\#(id)","model":"\#(model)"}}"#
}
