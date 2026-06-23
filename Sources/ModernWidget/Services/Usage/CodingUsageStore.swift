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
    @ObservationIgnored
    private var lastFingerprint: CodingUsageFingerprint?

    init() {
        loader = CodingUsageLoader()
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
        let scan = await Task.detached(priority: .utility) {
            loader.usageScan(scope: scope)
        }.value

        if Task.isCancelled || scan.fingerprint == lastFingerprint {
            return
        }

        let report = await Task.detached(priority: .utility) {
            loader.loadReport(scan: scan)
        }.value

        if Task.isCancelled {
            return
        }
        lastFingerprint = scan.fingerprint
        self.report = report
    }
}
