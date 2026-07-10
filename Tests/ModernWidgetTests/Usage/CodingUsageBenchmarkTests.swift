import Darwin
import Dispatch
import Foundation
import Testing

@testable import ModernWidget

@Suite("Coding usage benchmark")
struct CodingUsageBenchmarkTests {
    @Test(
        "measures coding usage startup and refresh paths",
        .enabled(if: ProcessInfo.processInfo.environment["CODING_USAGE_BENCHMARK"] == "1")
    )
    func measuresCodingUsageStartupAndRefreshPaths() async throws {
        let options = CodingUsageBenchmarkOptions(
            environment: ProcessInfo.processInfo.environment)
        let context = try CodingUsageBenchmarkContext(options: options)
        defer { context.cleanUp() }

        let loader = CodingUsageLoader(
            environment: context.environment,
            homeDirectory: context.homeDirectory
        )
        let referenceScan = loader.usageScan(scope: context.scope)
        var sink = CodingUsageBenchmarkSink()
        sink.consume(referenceScan)

        CodingUsageBenchmarkPrinter.printHeader(
            options: options,
            scan: referenceScan
        )

        try await CodingUsageBenchmarkRunner.run(
            name: "scan",
            options: options,
            maxP95Milliseconds: options.maxScanP95Milliseconds
        ) {
            let scan = loader.usageScan(scope: context.scope)
            sink.consume(scan)
        }

        try await CodingUsageBenchmarkRunner.run(
            name: "load.cold",
            options: options,
            maxP95Milliseconds: options.maxLoadP95Milliseconds
        ) {
            let coldLoader = CodingUsageLoader(
                environment: context.environment,
                homeDirectory: context.homeDirectory
            )
            let report = coldLoader.loadReport(scan: referenceScan)
            sink.consume(report)
        }

        sink.consume(loader.loadReport(scan: referenceScan))
        try await CodingUsageBenchmarkRunner.run(
            name: "load.cached",
            options: options,
            maxP95Milliseconds: options.maxCachedLoadP95Milliseconds
        ) {
            let report = loader.loadReport(scan: referenceScan)
            sink.consume(report)
        }

        try await CodingUsageBenchmarkRunner.run(
            name: "startup.cold",
            options: options,
            maxP95Milliseconds: options.maxStartupP95Milliseconds
        ) {
            let coldLoader = CodingUsageLoader(
                environment: context.environment,
                homeDirectory: context.homeDirectory
            )
            let scan = coldLoader.usageScan(scope: context.scope)
            let report = coldLoader.loadReport(scan: scan)
            sink.consume(scan)
            sink.consume(report)
        }

        try await CodingUsageBenchmarkRunner.run(
            name: "refresh.no_change",
            options: options,
            maxP95Milliseconds: options.maxRefreshP95Milliseconds
        ) {
            let scan = loader.usageScan(scope: context.scope)
            sink.consume(scan)
        }

        print("checksum \(sink.value)")
    }
}

private struct CodingUsageBenchmarkOptions {
    let mode: String
    let iterations: Int
    let warmups: Int
    let fixtureFiles: Int
    let fixtureLines: Int
    let maxScanP95Milliseconds: Double?
    let maxLoadP95Milliseconds: Double?
    let maxCachedLoadP95Milliseconds: Double?
    let maxStartupP95Milliseconds: Double?
    let maxRefreshP95Milliseconds: Double?

    init(environment: [String: String]) {
        let rawMode = environment["CODING_USAGE_BENCHMARK_MODE"] ?? "real"
        mode = rawMode == "fixture" ? "fixture" : "real"
        iterations = Self.integer(
            environment["CODING_USAGE_BENCHMARK_ITERATIONS"],
            defaultValue: 5,
            minimum: 1
        )
        warmups = Self.integer(
            environment["CODING_USAGE_BENCHMARK_WARMUPS"],
            defaultValue: 1,
            minimum: 0
        )
        fixtureFiles = Self.integer(
            environment["CODING_USAGE_BENCHMARK_FIXTURE_FILES"],
            defaultValue: 90,
            minimum: 3
        )
        fixtureLines = Self.integer(
            environment["CODING_USAGE_BENCHMARK_FIXTURE_LINES"],
            defaultValue: 400,
            minimum: 1
        )
        maxScanP95Milliseconds = Self.double(
            environment["CODING_USAGE_BENCHMARK_MAX_SCAN_P95_MS"])
        maxLoadP95Milliseconds = Self.double(
            environment["CODING_USAGE_BENCHMARK_MAX_LOAD_P95_MS"])
        maxCachedLoadP95Milliseconds = Self.double(
            environment["CODING_USAGE_BENCHMARK_MAX_CACHED_LOAD_P95_MS"])
        maxStartupP95Milliseconds = Self.double(
            environment["CODING_USAGE_BENCHMARK_MAX_STARTUP_P95_MS"])
        maxRefreshP95Milliseconds = Self.double(
            environment["CODING_USAGE_BENCHMARK_MAX_REFRESH_P95_MS"])
    }

    private static func integer(
        _ value: String?,
        defaultValue: Int,
        minimum: Int
    ) -> Int {
        guard let value, let parsed = Int(value) else {
            return defaultValue
        }
        return max(parsed, minimum)
    }

    private static func double(_ value: String?) -> Double? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return Double(value)
    }
}

private struct CodingUsageBenchmarkContext {
    let environment: [String: String]
    let homeDirectory: URL
    let scope: CodingUsageDateScope

    private let temporaryRoot: URL?

    init(options: CodingUsageBenchmarkOptions) throws {
        switch options.mode {
        case "real":
            environment = ProcessInfo.processInfo.environment
            homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            scope = CodingUsageDateScope()
            temporaryRoot = nil
        default:
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "CodingUsageBenchmark.\(UUID().uuidString)",
                isDirectory: true
            )
            let benchmarkScope = CodingUsageDateScope(
                now: date(2026, 6, 18, 12),
                calendar: gregorianUTC(firstWeekday: 2)
            )
            try CodingUsageBenchmarkFixture.write(
                root: root,
                scope: benchmarkScope,
                files: options.fixtureFiles,
                lines: options.fixtureLines
            )

            environment = [:]
            homeDirectory = root
            scope = benchmarkScope
            temporaryRoot = root
        }
    }

    func cleanUp() {
        guard let temporaryRoot else {
            return
        }
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

}

private enum CodingUsageBenchmarkFixture {
    static func write(
        root: URL,
        scope: CodingUsageDateScope,
        files: Int,
        lines: Int
    ) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeCodexConfig(root: root, modifiedAt: scope.now)

        for index in 0..<files {
            try writeUsageFile(root: root, index: index, lines: lines, scope: scope)
        }
    }

    private static func writeCodexConfig(root: URL, modifiedAt: Date) throws {
        try write(
            #"service_tier = "standard""#,
            to: root.appendingPathComponent(".codex/config.toml"),
            modifiedAt: modifiedAt
        )
    }

    private static func writeUsageFile(
        root: URL,
        index: Int,
        lines: Int,
        scope: CodingUsageDateScope
    ) throws {
        var text = ""
        text.reserveCapacity(lines * 260)
        for line in 0..<lines {
            let timestamp = timestamp(line: line, scope: scope)
            text += lineJSON(agent: index % 3, index: index, line: line, timestamp: timestamp)
        }
        try write(
            text,
            to: root.appendingPathComponent(path(agent: index % 3, index: index)),
            modifiedAt: scope.now
        )
    }

    private static func lineJSON(
        agent: Int,
        index: Int,
        line: Int,
        timestamp: String
    ) -> String {
        switch agent {
        case 0:
            return
                #"{"timestamp":""# + timestamp
                + #"","version":"1.2.3","sessionId":"session-\#(index)","requestId":"req-\#(index)-\#(line)","message":{"id":"msg-\#(index)-\#(line)","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":20,"cache_creation_input_tokens":10,"cache_read_input_tokens":30}}}"#
                + "\n"
        case 1:
            return
                #"{"timestamp":""# + timestamp
                + #"","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":120,"cached_input_tokens":40,"output_tokens":30,"reasoning_output_tokens":8,"total_tokens":150},"model":"gpt-5.2-codex"}}}"#
                + "\n"
        default:
            return
                #"{"type":"message","timestamp":""# + timestamp
                + #"","message":{"role":"assistant","model":"gpt-5.2","usage":{"input":100,"output":40,"cacheRead":20,"cacheWrite":10,"totalTokens":170}}}"#
                + "\n"
        }
    }

    private static func path(agent: Int, index: Int) -> String {
        switch agent {
        case 0:
            return ".claude/projects/project-\(index)/session-\(index)/chat.jsonl"
        case 1:
            return ".codex/sessions/2026/06/session-\(index).jsonl"
        default:
            return ".pi/agent/sessions/project-\(index)/prefix_session-\(index).jsonl"
        }
    }

    private static func timestamp(line: Int, scope: CodingUsageDateScope) -> String {
        let day = max(0, scope.historyDays.count - 1 - line % 30)
        let date = scope.historyDays[day].addingTimeInterval(TimeInterval(line % 86_400))
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
            components.year!,
            components.month!,
            components.day!,
            components.hour!,
            components.minute!,
            components.second!
        )
    }

    private static func write(_ text: String, to url: URL, modifiedAt: Date) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: url.path
        )
    }
}

private enum CodingUsageBenchmarkRunner {
    static func run(
        name: String,
        options: CodingUsageBenchmarkOptions,
        maxP95Milliseconds: Double?,
        body: () async throws -> Void
    ) async throws {
        for _ in 0..<options.warmups {
            CodingUsageBenchmarkPrinter.printProgress(name: name, phase: "warmup")
            try await body()
        }

        var samples: [Double] = []
        samples.reserveCapacity(options.iterations)
        for _ in 0..<options.iterations {
            CodingUsageBenchmarkPrinter.printProgress(
                name: name,
                phase: "run \(samples.count + 1)/\(options.iterations)"
            )
            let startedAt = DispatchTime.now().uptimeNanoseconds
            try await body()
            let endedAt = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(endedAt - startedAt) / 1_000_000)
        }

        let result = CodingUsageBenchmarkResult(samples: samples)
        CodingUsageBenchmarkPrinter.printResult(name: name, result: result)

        if let maxP95Milliseconds {
            #expect(
                result.p95Milliseconds <= maxP95Milliseconds,
                "\(name) p95 \(result.p95Milliseconds) ms exceeds \(maxP95Milliseconds) ms"
            )
        }
    }
}

private struct CodingUsageBenchmarkResult {
    let samples: [Double]

    var minimumMilliseconds: Double { samples.min() ?? 0 }
    var maximumMilliseconds: Double { samples.max() ?? 0 }
    var meanMilliseconds: Double {
        guard !samples.isEmpty else {
            return 0
        }
        return samples.reduce(0, +) / Double(samples.count)
    }
    var p50Milliseconds: Double { percentile(0.50) }
    var p95Milliseconds: Double { percentile(0.95) }

    private func percentile(_ value: Double) -> Double {
        guard !samples.isEmpty else {
            return 0
        }
        let sorted = samples.sorted()
        let index = Int((Double(sorted.count - 1) * value).rounded(.up))
        return sorted[min(index, sorted.count - 1)]
    }
}

private enum CodingUsageBenchmarkPrinter {
    static func printHeader(
        options: CodingUsageBenchmarkOptions,
        scan: CodingUsageScan
    ) {
        let files = scan.fingerprint.files
        let bytes = files.reduce(0) { total, file in
            total + (file.byteCount ?? 0)
        }
        let codexFileCount = scan.codexSources.reduce(0) { total, source in
            total + source.files.count
        }
        print("")
        print("coding usage benchmark")
        print("mode \(options.mode)")
        print("iterations \(options.iterations)")
        print("warmups \(options.warmups)")
        print("history_days \(scan.scope.historyDays.count)")
        print("files.total \(files.count)")
        print("files.claude \(scan.claudeFiles.count)")
        print("files.codex \(codexFileCount)")
        print("files.pi \(scan.piFiles.count)")
        print("bytes \(bytes)")
        print("")
        print("metric,min_ms,mean_ms,p50_ms,p95_ms,max_ms")
        fflush(stdout)
    }

    static func printResult(name: String, result: CodingUsageBenchmarkResult) {
        print(
            [
                name,
                milliseconds(result.minimumMilliseconds),
                milliseconds(result.meanMilliseconds),
                milliseconds(result.p50Milliseconds),
                milliseconds(result.p95Milliseconds),
                milliseconds(result.maximumMilliseconds),
            ].joined(separator: ",")
        )
        fflush(stdout)
    }

    static func printProgress(name: String, phase: String) {
        print("# \(name) \(phase)")
        fflush(stdout)
    }

    private static func milliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

private struct CodingUsageBenchmarkSink {
    private(set) var value: UInt64 = 0

    mutating func consume(_ scan: CodingUsageScan) {
        value &+= UInt64(scan.fingerprint.files.count)
        value &+= UInt64(scan.claudeFiles.count)
        value &+= UInt64(scan.piFiles.count)
        value &+= UInt64(scan.codexSources.count)
    }

    mutating func consume(_ report: CodingUsageReport) {
        for agent in report.agents {
            value &+= agent.totalCounts.totalTokens
        }
    }
}
