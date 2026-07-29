import Foundation
import Testing

@testable import ModernWidget

@Suite("Claude usage loader")
struct ClaudeUsageLoaderTests {
    @Test(
        "uses the official input rate for every supported Claude model family",
        arguments: [
            (model: "claude-fable-5", inputCost: 10.0),
            (model: "claude-mythos-5", inputCost: 10.0),
            (model: "claude-opus-5", inputCost: 5.0),
            (model: "claude-opus-4-8", inputCost: 5.0),
            (model: "claude-opus-4-7", inputCost: 5.0),
            (model: "claude-opus-4-6", inputCost: 5.0),
            (model: "claude-sonnet-5", inputCost: 3.0),
            (model: "claude-haiku-4-5", inputCost: 1.0),
        ])
    func pricesSupportedModelFamilies(expectation: (model: String, inputCost: Double)) throws {
        try withUsageHome { home in
            let line =
                #"{"timestamp":"2026-06-18T02:00:00.000Z","message":{"role":"assistant","id":"msg","model":"\#(expectation.model)","usage":{"input_tokens":100000,"output_tokens":0}}}"#
            try writeCodingUsageFixture(line, to: ".claude/projects/p/session.jsonl", in: home)

            let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

            #expect(
                abs(totals.costUSD - expectation.inputCost / 10) < 0.000_001,
                "unexpected input price for \(expectation.model)"
            )
        }
    }

    @Test("prices normal input, output, and both cache durations")
    func pricesClaudeTokenCategories() throws {
        try withUsageHome { home in
            let line =
                #"{"timestamp":"2026-06-18T02:00:00.000Z","requestId":"req","isSidechain":false,"message":{"role":"assistant","id":"msg","model":"claude-sonnet-5","usage":{"input_tokens":1000000,"output_tokens":1000000,"cache_creation_input_tokens":9000000,"cache_creation":{"ephemeral_5m_input_tokens":1000000,"ephemeral_1h_input_tokens":1000000},"cache_read_input_tokens":1000000}}}"#
            try writeCodingUsageFixture(line, to: ".claude/projects/p/session.jsonl", in: home)

            let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

            #expect(totals.totalTokens == 5_000_000)
            #expect(abs(totals.costUSD - 28.05) < 0.000_001)
        }
    }

    @Test("applies the persisted data residency modifier")
    func appliesClaudeDataResidency() throws {
        try withUsageHome { home in
            let line =
                #"{"timestamp":"2026-07-14T02:00:00.000Z","message":{"role":"assistant","id":"msg","model":"claude-opus-4-8","usage":{"input_tokens":1000000,"output_tokens":1000000,"inference_geo":"us"}}}"#
            let scope = codingUsageScope(now: date(2026, 7, 14, 12))
            try writeCodingUsageFixture(
                line,
                to: ".claude/projects/p/session.jsonl",
                in: home,
                modifiedAt: scope.now
            )

            let totals = codingUsageTotals(
                in: loadCodingUsage(from: home, scope: scope),
                for: .claude
            )

            #expect(totals.totalTokens == 2_000_000)
            #expect(abs(totals.costUSD - 33) < 0.000_001)
        }
    }

    @Test("residency-ineligible models keep the regular price under a US geo")
    func ignoresDataResidencyForIneligibleModels() throws {
        try withUsageHome { home in
            let line =
                #"{"timestamp":"2026-07-14T02:00:00.000Z","message":{"role":"assistant","id":"msg","model":"claude-haiku-4-5","usage":{"input_tokens":1000000,"output_tokens":1000000,"inference_geo":"us"}}}"#
            let scope = codingUsageScope(now: date(2026, 7, 14, 12))
            try writeCodingUsageFixture(
                line,
                to: ".claude/projects/p/session.jsonl",
                in: home,
                modifiedAt: scope.now
            )

            let totals = codingUsageTotals(
                in: loadCodingUsage(from: home, scope: scope),
                for: .claude
            )

            #expect(totals.totalTokens == 2_000_000)
            #expect(abs(totals.costUSD - 6) < 0.000_001)
        }
    }

    @Test("deduplicates main-chain and sidechain copies")
    func deduplicatesSidechainCopies() throws {
        try withUsageHome { home in
            let log = [
                #"{"timestamp":"2026-06-18T02:00:00.000Z","requestId":"req","isSidechain":true,"message":{"role":"assistant","id":"msg","model":"claude-opus-4-8","usage":{"input_tokens":900,"output_tokens":100}}}"#,
                #"{"timestamp":"2026-06-18T02:00:01.000Z","requestId":"req","isSidechain":false,"message":{"role":"assistant","id":"msg","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":20}}}"#,
            ].joined(separator: "\n")
            try writeCodingUsageFixture(log, to: ".claude/projects/p/session.jsonl", in: home)

            let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

            #expect(totals.totalTokens == 120)
            #expect(abs(totals.costUSD - 0.001) < 0.000_000_1)
        }
    }

    @Test("omits unknown models instead of emitting partial usage")
    func omitsUnknownClaudeModels() throws {
        try withUsageHome { home in
            let line =
                #"{"timestamp":"2026-06-18T02:00:00.000Z","message":{"role":"assistant","id":"msg","model":"claude-opus-4-99","usage":{"input_tokens":100,"output_tokens":20}}}"#
            try writeCodingUsageFixture(line, to: ".claude/projects/p/session.jsonl", in: home)

            let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

            #expect(!totals.hasUsage)
        }
    }

    @Test("treats the legacy flat cache field as a five minute write")
    func readsLegacyFlatCacheWrites() throws {
        try withUsageHome { home in
            let line =
                #"{"timestamp":"2026-06-18T02:00:00.000Z","message":{"role":"assistant","id":"msg","model":"claude-opus-4-8","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":1000000}}}"#
            try writeCodingUsageFixture(line, to: ".claude/projects/p/session.jsonl", in: home)

            let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

            #expect(totals.totalTokens == 1_000_000)
            #expect(abs(totals.costUSD - 6.25) < 0.000_001)
        }
    }

    @Test("counts only assistant message usage")
    func ignoresNonAssistantUsage() throws {
        try withUsageHome { home in
            let line =
                #"{"timestamp":"2026-06-18T02:00:00.000Z","message":{"role":"user","id":"msg","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":20}}}"#
            try writeCodingUsageFixture(line, to: ".claude/projects/p/session.jsonl", in: home)

            let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

            #expect(!totals.hasUsage)
        }
    }

    @Test("rejects incomplete records and malformed token fields")
    func rejectsMalformedUsage() throws {
        try withUsageHome { home in
            let log = [
                #"{"timestamp":"2026-06-18T02:00:00.000Z","message":{"role":"assistant","id":"truncated","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":20}}"#,
                #"{"timestamp":"2026-06-18T02:01:00.000Z","message":{"role":"assistant","id":"malformed","model":"claude-opus-4-8","usage":{"input_tokens":"100","output_tokens":20}}}"#,
            ].joined(separator: "\n")
            try writeCodingUsageFixture(log, to: ".claude/projects/p/session.jsonl", in: home)

            let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

            #expect(!totals.hasUsage)
        }
    }
}
