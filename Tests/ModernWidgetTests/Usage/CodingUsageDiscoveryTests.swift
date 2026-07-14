import Foundation
import Testing

@testable import ModernWidget

@Suite("Coding usage discovery")
struct CodingUsageDiscoveryTests {
    @Test("detects installed providers from their data roots")
    func detectsInstalledProviders() throws {
        let home = try makeFixtureRoot("CodingUsageInstalledProviders")
        defer { try? FileManager.default.removeItem(at: home) }
        for path in [".claude/projects", ".codex", ".pi/agent/sessions"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(path),
                withIntermediateDirectories: true
            )
        }

        let installed = CodingUsageLoader(environment: [:], homeDirectory: home).installedAgents()

        #expect(installed == Set(CodingUsageAgent.allCases))
    }

    @Test("does not scan disabled providers")
    func skipsDisabledProviders() throws {
        let home = try makeFixtureRoot("CodingUsageDisabledProviders")
        defer { try? FileManager.default.removeItem(at: home) }
        try writeCodingUsageFixture(
            "{}",
            to: ".claude/projects/p/session.jsonl",
            in: home
        )
        try writeCodingUsageFixture("{}", to: ".codex/sessions/session.jsonl", in: home)
        try writeCodingUsageFixture("{}", to: ".pi/agent/sessions/p/session.jsonl", in: home)

        let scan = CodingUsageLoader(environment: [:], homeDirectory: home).usageScan(
            scope: codingUsageScope(),
            enabledAgents: [.codex]
        )

        #expect(scan.installedAgents == Set(CodingUsageAgent.allCases))
        #expect(scan.claude.files.isEmpty)
        #expect(scan.codex.sources.flatMap(\.files).count == 1)
        #expect(scan.pi.files.isEmpty)
        #expect(scan.fingerprint.agents == [.codex])
    }

    @Test("filters stale files before parsing")
    func filtersStaleFiles() throws {
        let home = try makeFixtureRoot("CodingUsageStaleFiles")
        defer { try? FileManager.default.removeItem(at: home) }
        try writeCodingUsageFixture(
            "not json",
            to: ".pi/agent/sessions/p/old.jsonl",
            in: home,
            modifiedAt: date(2026, 5, 1)
        )

        let scan = CodingUsageLoader(environment: [:], homeDirectory: home).usageScan(
            scope: codingUsageScope()
        )

        #expect(scan.pi.files.isEmpty)
        #expect(scan.fingerprint.files.isEmpty)
    }

    @Test("environment overrides accept a Claude projects directory")
    func acceptsClaudeProjectsOverride() throws {
        let home = try makeFixtureRoot("CodingUsageClaudeOverrideHome")
        let custom = try makeFixtureRoot("CodingUsageClaudeOverrideData")
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: custom)
        }
        let projects = custom.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)

        let loader = CodingUsageLoader(
            environment: ["CLAUDE_CONFIG_DIR": projects.path],
            homeDirectory: home
        )

        #expect(loader.installedAgents() == [.claude])
    }

    @Test("loads files under overlapping configured roots once")
    func deduplicatesOverlappingRoots() throws {
        let home = try makeFixtureRoot("CodingUsageOverlappingRoots")
        defer { try? FileManager.default.removeItem(at: home) }

        let claudeConfig = home.appendingPathComponent("claude")
        let nestedClaudeConfig = claudeConfig.appendingPathComponent("projects/p")
        try writeCodingUsageFixture(
            #"{"timestamp":"2026-06-18T02:00:00.000Z","message":{"id":"msg","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":20}}}"#,
            to: "projects/session.jsonl",
            in: nestedClaudeConfig
        )

        let piSessions = home.appendingPathComponent("pi-sessions")
        let nestedPiSessions = piSessions.appendingPathComponent("p")
        try writeCodingUsageFixture(
            piFixture(tokens: 100),
            to: "session.jsonl",
            in: nestedPiSessions
        )

        let report = loadCodingUsage(
            from: home,
            environment: [
                "CLAUDE_CONFIG_DIR": "\(claudeConfig.path),\(nestedClaudeConfig.path)",
                "PI_AGENT_DIR": "\(piSessions.path),\(nestedPiSessions.path)",
            ]
        )

        #expect(codingUsageTotals(in: report, for: .claude).totalTokens == 120)
        #expect(codingUsageTotals(in: report, for: .pi).totalTokens == 100)
    }

    @Test("file changes alter the refresh fingerprint")
    func fingerprintsFileChanges() throws {
        let home = try makeFixtureRoot("CodingUsageFingerprint")
        defer { try? FileManager.default.removeItem(at: home) }
        let path = ".pi/agent/sessions/p/session.jsonl"
        try writeCodingUsageFixture("{}", to: path, in: home)
        let loader = CodingUsageLoader(environment: [:], homeDirectory: home)
        let before = loader.usageScan(scope: codingUsageScope()).fingerprint
        try writeCodingUsageFixture(
            "{\"changed\":true}",
            to: path,
            in: home,
            modifiedAt: date(2026, 6, 18, 13)
        )

        let after = loader.usageScan(scope: codingUsageScope()).fingerprint

        #expect(before != after)
    }

    @Test("unchanged files reuse parsed records while deleted files disappear")
    func refreshesChangedAndDeletedFiles() throws {
        let home = try makeFixtureRoot("CodingUsageRefresh")
        defer { try? FileManager.default.removeItem(at: home) }
        let path = ".pi/agent/sessions/p/session.jsonl"
        try writeCodingUsageFixture(piFixture(tokens: 100), to: path, in: home)
        let loader = CodingUsageLoader(environment: [:], homeDirectory: home)
        let scope = codingUsageScope()
        let first = loader.loadReport(scan: loader.usageScan(scope: scope))
        try writeCodingUsageFixture(
            piFixture(tokens: 250),
            to: path,
            in: home,
            modifiedAt: date(2026, 6, 18, 13)
        )
        let changed = loader.loadReport(scan: loader.usageScan(scope: scope))
        try FileManager.default.removeItem(at: home.appendingPathComponent(path))
        let deleted = loader.loadReport(scan: loader.usageScan(scope: scope))

        #expect(codingUsageTotals(in: first, for: .pi).totalTokens == 100)
        #expect(codingUsageTotals(in: changed, for: .pi).totalTokens == 250)
        #expect(!codingUsageTotals(in: deleted, for: .pi).hasUsage)
    }
}

private func piFixture(tokens: UInt64) -> String {
    #"{"type":"message","timestamp":"2026-06-18T02:00:00.000Z","message":{"role":"assistant","usage":{"totalTokens":\#(tokens),"cost":{"total":0.1}}}}"#
}
