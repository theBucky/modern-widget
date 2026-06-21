import AppKit
import SwiftUI

struct CodingUsageAgentLogo: View {
    let agent: CodingUsageAgent
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if let url = Bundle.main.url(forResource: agent.logoResourceName, withExtension: "pdf"),
            let image = NSImage(contentsOf: url)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
