import Foundation
import Observation

@MainActor
@Observable
final class CodingUsageStore {
    private static let refreshInterval: TimeInterval = 600

    private(set) var report = CodingUsageReport.empty

    @ObservationIgnored
    private let loader: CodingUsageLoader
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        loader = CodingUsageLoader(environment: environment, homeDirectory: homeDirectory)
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reload()
                do {
                    try await Task.sleep(for: .seconds(Self.refreshInterval))
                } catch {
                    return
                }
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    private func reload() async {
        let loader = self.loader
        let scope = CodingUsageDateScope()
        let report = await Task.detached(priority: .utility) {
            loader.loadReport(scope: scope)
        }.value

        if Task.isCancelled {
            return
        }
        self.report = report
    }
}
