import Foundation
import Testing

@testable import ModernWidget

@Suite("Codex usage loader")
struct CodexUsageLoaderTests {
    @Test("uses separate official OpenAI and xAI input price catalogs")
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
            ("grok-4.5", 2),
        ]

        for expectation in cases {
            let home = try makeFixtureRoot("CodexUsagePricing-\(expectation.model)")
            defer { try? FileManager.default.removeItem(at: home) }
            let line = tokenCount(
                at: "2026-06-18T01:00:00.000Z",
                input: 100_000,
                cached: 0,
                output: 0,
                model: expectation.model
            )
            try writeCodingUsageFixture(line, to: ".codex/sessions/session.jsonl", in: home)

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
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"model":"gpt-5.3-codex"}}}"#
        try writeCodingUsageFixture(
            [line, line.replacingOccurrences(of: "01:00:00", with: "01:01:00")]
                .joined(separator: "\n"),
            to: ".codex/sessions/session.jsonl",
            in: home
        )

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 240)
        #expect(abs(totals.costUSD - 0.000_878_5) < 0.000_000_001)
    }

    @Test("resumes cumulative accounting after a context reset")
    func resumesAfterCumulativeReset() throws {
        let home = try makeFixtureRoot("CodexUsageCumulativeReset")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            tokenCount(
                at: "2026-06-18T01:00:00.000Z",
                input: 100,
                cached: 10,
                output: 20,
                model: "gpt-5.3-codex"
            ),
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

    @Test("uses xAI long-context pricing independently from OpenAI")
    func pricesGrokLongContext() throws {
        let home = try makeFixtureRoot("CodexUsageGrokLongContext")
        defer { try? FileManager.default.removeItem(at: home) }
        let line = tokenCount(
            at: "2026-06-18T01:01:00.000Z",
            input: 300_000,
            cached: 100_000,
            output: 100_000,
            model: "grok-4.5"
        )
        try writeCodingUsageFixture(line, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 400_000)
        #expect(abs(totals.costUSD - 2.1) < 0.000_001)
    }

    @Test("prices Grok records with xAI rates")
    func pricesGrokRecords() throws {
        let home = try makeFixtureRoot("CodexUsageGrok")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"turn_context","payload":{"model":"grok-4.5"}}"#,
            tokenCount(at: "2026-06-18T01:01:00.000Z", input: 1_000, cached: 400, output: 200),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 1_200)
        #expect(abs(totals.costUSD - 0.0026) < 0.000_000_1)
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

    @Test("suppresses inherited history in a forked rollout")
    func suppressesForkReplay() throws {
        let home = try makeFixtureRoot("CodexUsageForkReplay")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"session_meta","payload":{"id":"fork","forked_from_id":"origin"}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"session_meta","payload":{"id":"origin"}}"#,
            tokenCount(at: "2026-06-18T01:00:00.100Z", input: 1_000, cached: 100, output: 200),
            tokenCount(
                at: "2026-06-18T01:01:00.000Z",
                input: 1_600,
                cached: 160,
                output: 320,
                model: "gpt-5.3-codex"
            ),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/fork.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 720)
    }

    @Test("suppresses inherited history identified by structured subagent metadata")
    func suppressesStructuredSubagentReplay() throws {
        let home = try makeFixtureRoot("CodexUsageSubagentReplay")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"session_meta","payload":{"id":"child","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}}}"#,
            #"{"timestamp":"2026-06-18T01:00:00.000Z","type":"session_meta","payload":{"id":"parent"}}"#,
            tokenCount(at: "2026-06-18T01:00:00.100Z", input: 1_000, cached: 100, output: 200),
            tokenCount(
                at: "2026-06-18T01:01:00.000Z",
                input: 1_600,
                cached: 160,
                output: 320,
                model: "gpt-5.3-codex"
            ),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".codex/sessions/subagent.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 720)
    }

    @Test("active sessions take precedence over archived copies")
    func activeSessionsTakePrecedence() throws {
        let home = try makeFixtureRoot("CodexUsageArchiveDedupe")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = tokenCount(
            at: "2026-06-18T01:00:00.000Z",
            input: 100,
            cached: 0,
            output: 20,
            model: "gpt-5.3-codex"
        )
        try writeCodingUsageFixture(log, to: ".codex/sessions/day/session.jsonl", in: home)
        try writeCodingUsageFixture(
            log,
            to: ".codex/archived_sessions/day/session.jsonl",
            in: home
        )

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .codex)

        #expect(totals.totalTokens == 120)
    }
}

private func tokenCount(
    at timestamp: String,
    input: UInt64,
    cached: UInt64,
    output: UInt64,
    model: String? = nil
) -> String {
    let modelField = model.map { #","model":"\#($0)""# } ?? ""
    return
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(input + output)}\#(modelField)}}}"#
}
