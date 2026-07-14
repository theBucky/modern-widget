import Foundation
import Testing

@testable import ModernWidget

@Suite("Pi usage loader")
struct PiUsageLoaderTests {
    @Test("uses Pi's persisted token and cost totals")
    func usesPersistedTotals() throws {
        let home = try makeFixtureRoot("PiUsagePersistedTotals")
        defer { try? FileManager.default.removeItem(at: home) }
        let line =
            #"{"type":"message","timestamp":"2026-06-18T02:00:00.000Z","message":{"role":"assistant","model":"unknown-future-model","usage":{"input":999999,"output":888888,"cacheRead":777777,"cacheWrite":666666,"totalTokens":123,"cost":{"input":9,"output":8,"cacheRead":7,"cacheWrite":6,"total":0.42}}}}"#
        try writeCodingUsageFixture(line, to: ".pi/agent/sessions/p/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .pi)

        #expect(totals.totalTokens == 123)
        #expect(totals.costUSD == 0.42)
    }

    @Test("sums assistant messages and ignores other roles")
    func sumsAssistantMessages() throws {
        let home = try makeFixtureRoot("PiUsageAssistantMessages")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            piLine(role: "assistant", tokens: 100, cost: 0.25),
            piLine(role: "user", tokens: 900, cost: 9),
            piLine(role: "assistant", tokens: 50, cost: 0.125),
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".pi/agent/sessions/p/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .pi)

        #expect(totals.totalTokens == 150)
        #expect(totals.costUSD == 0.375)
    }

    @Test("omits records without authoritative totals")
    func omitsIncompleteRecords() throws {
        let home = try makeFixtureRoot("PiUsageIncomplete")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = [
            #"{"type":"message","timestamp":"2026-06-18T02:00:00.000Z","message":{"role":"assistant","usage":{"totalTokens":100}}}"#,
            #"{"type":"message","timestamp":"2026-06-18T02:01:00.000Z","message":{"role":"assistant","usage":{"cost":{"total":0.2}}}}"#,
            #"{"type":"message","timestamp":"2026-06-18T02:02:00.000Z","message":{"role":"assistant","usage":{"total_tokens":100,"cost":{"total":0.2}}}}"#,
        ].joined(separator: "\n")
        try writeCodingUsageFixture(log, to: ".pi/agent/sessions/p/session.jsonl", in: home)

        let totals = codingUsageTotals(in: loadCodingUsage(from: home), for: .pi)

        #expect(!totals.hasUsage)
    }
}

private func piLine(role: String, tokens: UInt64, cost: Double) -> String {
    #"{"type":"message","timestamp":"2026-06-18T02:00:00.000Z","message":{"role":"\#(role)","usage":{"totalTokens":\#(tokens),"cost":{"total":\#(cost)}}}}"#
}
