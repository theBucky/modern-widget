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

        let installed = CodingUsageLoader(homeDirectory: home).installedAgents()

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

        let scan = CodingUsageLoader(homeDirectory: home).usageScan(
            scope: codingUsageScope(),
            enabledAgents: [.codex]
        )

        #expect(scan.installedAgents == Set(CodingUsageAgent.allCases))
        #expect(scan.claude.files.isEmpty)
        #expect(scan.codex.files.count == 1)
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

        let scan = CodingUsageLoader(homeDirectory: home).usageScan(
            scope: codingUsageScope()
        )

        #expect(scan.pi.files.isEmpty)
        #expect(scan.fingerprint.files.isEmpty)
    }

    @Test("file changes alter the refresh fingerprint")
    func fingerprintsFileChanges() throws {
        let home = try makeFixtureRoot("CodingUsageFingerprint")
        defer { try? FileManager.default.removeItem(at: home) }
        let path = ".pi/agent/sessions/p/session.jsonl"
        try writeCodingUsageFixture("{}", to: path, in: home)
        let loader = CodingUsageLoader(homeDirectory: home)
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
        let loader = CodingUsageLoader(homeDirectory: home)
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

    @Test("same-size rewrites with a preserved mtime invalidate parsed records")
    func refreshesInPlaceRewrites() throws {
        let home = try makeFixtureRoot("CodingUsageInPlaceRewrite")
        defer { try? FileManager.default.removeItem(at: home) }
        let relativePath = ".pi/agent/sessions/p/session.jsonl"
        let modifiedAt = date(2026, 6, 18, 12)
        try writeCodingUsageFixture(
            piFixture(tokens: 100),
            to: relativePath,
            in: home,
            modifiedAt: modifiedAt
        )
        let loader = CodingUsageLoader(homeDirectory: home)
        let scope = codingUsageScope()
        let firstScan = loader.usageScan(scope: scope)
        let first = loader.loadReport(scan: firstScan)

        let file = home.appendingPathComponent(relativePath)
        try piFixture(tokens: 250).write(to: file, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: file.path
        )
        let secondScan = loader.usageScan(scope: scope)
        let second = loader.loadReport(scan: secondScan)

        #expect(firstScan.fingerprint != secondScan.fingerprint)
        #expect(codingUsageTotals(in: first, for: .pi).totalTokens == 100)
        #expect(codingUsageTotals(in: second, for: .pi).totalTokens == 250)
    }
}

private func piFixture(tokens: UInt64) -> String {
    #"{"type":"message","timestamp":"2026-06-18T02:00:00.000Z","message":{"role":"assistant","usage":{"totalTokens":\#(tokens),"cost":{"total":0.1}}}}"#
}
