import Foundation
import Testing

@testable import ModernWidget

@MainActor
@Suite("Coding usage store")
struct CodingUsageStoreTests {
    private func makeStore(home: URL) -> CodingUsageStore {
        CodingUsageStore(
            defaults: makeDefaults("CodingUsageStoreTests"),
            loader: CodingUsageLoader(homeDirectory: home)
        )
    }

    @Test("an uninstalled agent reads off while its stored preference survives")
    func uninstalledAgentReadsOff() throws {
        try withUsageHome { home in
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(".claude/projects"),
                withIntermediateDirectories: true
            )

            let store = makeStore(home: home)

            #expect(store.installedAgents == [.claude])
            #expect(store.activeAgents == [.claude])
            #expect(store[agentActive: .claude])
            #expect(!store[agentActive: .codex])
            #expect(!store[agentActive: .pi])
            #expect(store.enabledAgents == Set(CodingUsageAgent.allCases))
            #expect(store.presentation.sections.map(\.agent) == [.claude])
        }
    }

    @Test("toggling an installed agent off drops it from active state and presentation")
    func togglingInstalledAgentOff() throws {
        try withUsageHome { home in
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(".claude/projects"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(".codex"),
                withIntermediateDirectories: true
            )

            let store = makeStore(home: home)
            store[agentActive: .codex] = false

            #expect(!store[agentActive: .codex])
            #expect(store.enabledAgents == [.claude, .pi])
            #expect(store.presentation.sections.map(\.agent) == [.claude])

            store[agentActive: .codex] = true

            #expect(store[agentActive: .codex])
            #expect(store.presentation.sections.map(\.agent) == [.claude, .codex])
        }
    }
}
