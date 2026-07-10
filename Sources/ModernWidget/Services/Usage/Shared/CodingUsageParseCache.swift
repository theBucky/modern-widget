import Synchronization

/// Keeps unchanged files from being reopened. Replacing each agent index after a load
/// also evicts deleted files and previous fingerprints without a separate cleanup pass.
final class CodingUsageParseCache: Sendable {
    private struct State: Sendable {
        var claude: [CodingUsageFileFingerprint: [ClaudeUsageEntry]] = [:]
        var codex: [CodingUsageFileFingerprint: [CodexUsageEvent]] = [:]
        var pi: [CodingUsageFileFingerprint: [PiUsageRecord]] = [:]
    }

    private let state = Mutex(State())

    func claudeRecords() -> [CodingUsageFileFingerprint: [ClaudeUsageEntry]] {
        state.withLock { $0.claude }
    }

    func replaceClaudeRecords(
        _ records: [CodingUsageFileFingerprint: [ClaudeUsageEntry]]
    ) {
        state.withLock { $0.claude = records }
    }

    func codexEvents() -> [CodingUsageFileFingerprint: [CodexUsageEvent]] {
        state.withLock { $0.codex }
    }

    func replaceCodexEvents(
        _ events: [CodingUsageFileFingerprint: [CodexUsageEvent]]
    ) {
        state.withLock { $0.codex = events }
    }

    func piRecords() -> [CodingUsageFileFingerprint: [PiUsageRecord]] {
        state.withLock { $0.pi }
    }

    func replacePiRecords(_ records: [CodingUsageFileFingerprint: [PiUsageRecord]]) {
        state.withLock { $0.pi = records }
    }
}
