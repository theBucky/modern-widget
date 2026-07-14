import Foundation
import Testing

@testable import ModernWidget

@Suite("Claude usage loader")
struct ClaudeUsageLoaderTests {
    @Test("uses the official input rate for every supported Claude model family")
    func pricesSupportedModelFamilies() throws {
        let cases: [(model: String, inputCost: Double)] = [
            ("claude-fable-5", 10),
            ("claude-mythos-5", 10),
            ("claude-opus-4-8", 5),
            ("claude-opus-4-7", 5),
            ("claude-opus-4-6", 5),
            ("claude-opus-4-5", 5),
            ("claude-sonnet-5", 3),
            ("claude-sonnet-4-6", 3),
            ("claude-sonnet-4-5", 3),
            ("claude-haiku-4-5", 1),
        ]

        for expectation in cases {
            let home = try makeFixtureRoot("ClaudeUsagePricing-\(expectation.model)")
            defer { try? FileManager.default.removeItem(at: home) }
            let line =
                #"{"timestamp":"2026-06-18T02:00:00.000Z","message":{"id":"msg","model":"\#(expectation.model)","usage":{"input_tokens":100000,"output_tokens":0}}}"#
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
        let home = try makeFixtureRoot("ClaudeUsageTokenCategories")
        defer { try? FileManager.default.removeItem(at: home) }
        let line =
            #"{"timestamp":"2026-06-18T02:00:00.000Z","requestId":"req","isSidechain":false,"message":{"id":"msg","model":"claude-sonnet-5","usage":{"input_tokens":1000000,"output_tokens":1000000,"cache_creation_input_tokens":9000000,"cache_creation":{"ephemeral_5m_input_tokens":1000000,"ephemeral_1h_input_tokens":1000000},"cache_read_input_tokens":1000000}}}"#
        try writeCodingUsageFixture(line, to: ".claude/projects/p/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

        #expect(totals.totalTokens == 5_000_000)
        #expect(abs(totals.costUSD - 28.05) < 0.000_001)
    }

    @Test("uses standard rates across the full Claude 4.6 context windows")
    func pricesFullClaude46ContextAtStandardRates() throws {
        let cases: [(model: String, expectedCost: Double)] = [
            ("claude-opus-4-6", 1.75),
            ("claude-sonnet-4-6", 1.05),
        ]

        for expectation in cases {
            let home = try makeFixtureRoot("ClaudeUsageFullContext-\(expectation.model)")
            defer { try? FileManager.default.removeItem(at: home) }
            let line =
                #"{"timestamp":"2026-06-18T02:00:00.000Z","message":{"id":"msg","model":"\#(expectation.model)","usage":{"input_tokens":300000,"output_tokens":10000}}}"#
            try writeCodingUsageFixture(line, to: ".claude/projects/p/session.jsonl", in: home)

            let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

            #expect(abs(totals.costUSD - expectation.expectedCost) < 0.000_001)
        }
    }

    @Test("applies Claude 4.5 long-context prices to one request")
    func pricesLongContextPerRequest() throws {
        let home = try makeFixtureRoot("ClaudeUsageLongContext")
        defer { try? FileManager.default.removeItem(at: home) }
        let line =
            #"{"timestamp":"2026-06-18T02:00:00.000Z","message":{"id":"msg","model":"claude-sonnet-4-5","usage":{"input_tokens":300000,"output_tokens":10000}}}"#
        try writeCodingUsageFixture(line, to: ".claude/projects/p/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

        #expect(totals.totalTokens == 310_000)
        #expect(abs(totals.costUSD - 2.025) < 0.000_001)
    }

    @Test("applies the persisted data residency modifier")
    func appliesClaudeDataResidency() throws {
        let home = try makeFixtureRoot("ClaudeUsageDataResidency")
        defer { try? FileManager.default.removeItem(at: home) }
        let line =
            #"{"timestamp":"2026-07-14T02:00:00.000Z","message":{"id":"msg","model":"claude-opus-4-8","usage":{"input_tokens":1000000,"output_tokens":1000000,"inference_geo":"us"}}}"#
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

    @Test("deduplicates main-chain and sidechain copies")
    func deduplicatesSidechainCopies() throws {
        let home = try makeFixtureRoot("ClaudeUsageDedupe")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"timestamp":"2026-06-18T02:00:00.000Z","requestId":"req","isSidechain":true,"message":{"id":"msg","model":"claude-opus-4-8","usage":{"input_tokens":900,"output_tokens":100}}}"#,
            #"{"timestamp":"2026-06-18T02:00:01.000Z","requestId":"req","isSidechain":false,"message":{"id":"msg","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":20}}}"#,
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".claude/projects/p/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

        #expect(totals.totalTokens == 120)
        #expect(abs(totals.costUSD - 0.001) < 0.000_000_1)
    }

    @Test("omits unknown models instead of emitting partial usage")
    func omitsUnknownClaudeModels() throws {
        let home = try makeFixtureRoot("ClaudeUsageUnknownModel")
        defer { try? FileManager.default.removeItem(at: home) }
        let line =
            #"{"timestamp":"2026-06-18T02:00:00.000Z","message":{"id":"msg","model":"claude-opus-4-99","usage":{"input_tokens":100,"output_tokens":20}}}"#
        try writeCodingUsageFixture(line, to: ".claude/projects/p/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

        #expect(!totals.hasUsage)
    }

    @Test("treats the legacy flat cache field as a five minute write")
    func readsLegacyFlatCacheWrites() throws {
        let home = try makeFixtureRoot("ClaudeUsageLegacyCache")
        defer { try? FileManager.default.removeItem(at: home) }
        let line =
            #"{"timestamp":"2026-06-18T02:00:00.000Z","message":{"id":"msg","model":"claude-opus-4-8","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":1000000}}}"#
        try writeCodingUsageFixture(line, to: ".claude/projects/p/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .claude)

        #expect(totals.totalTokens == 1_000_000)
        #expect(abs(totals.costUSD - 6.25) < 0.000_001)
    }
}
