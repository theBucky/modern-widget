import Foundation
import Testing

@testable import ModernWidget

@Suite("Coding usage agent logo")
struct CodingUsageAgentLogoTests {
    @Test("finds flattened packaged app resources")
    func findsFlattenedPackagedAppResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "CodingUsageAgentLogoTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("Fixture.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let logo = resources.appendingPathComponent("ClaudeLogo.pdf")
        try Data("pdf".utf8).write(to: logo)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundlePackageType</key>
          <string>APPL</string>
        </dict>
        </plist>
        """.write(
            to: app.appendingPathComponent("Contents/Info.plist"),
            atomically: true,
            encoding: .utf8
        )

        let bundle = try #require(Bundle(url: app))

        #expect(CodingUsageAgentLogo.logoURL(for: .claude, in: bundle) == logo)
    }
}
