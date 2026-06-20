import AppKit
import SwiftUI

struct CodingUsageAgentLogo: View {
    let agent: CodingUsageAgent
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if let image = Self.image(for: agent) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private static func image(for agent: CodingUsageAgent) -> NSImage? {
        logoURL(for: agent).flatMap(NSImage.init(contentsOf:))
    }

    nonisolated static func logoURL(for agent: CodingUsageAgent, in bundle: Bundle = .main) -> URL?
    {
        bundle.url(forResource: agent.logoResourceName, withExtension: "pdf")?.standardizedFileURL
    }
}
