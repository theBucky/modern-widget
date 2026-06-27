import AppKit
import SwiftUI

struct CodingUsageValueText: View {
    let counts: CodingTokenCounts
    let isLoading: Bool

    var body: some View {
        if isLoading {
            Text("loading")
                .foregroundColor(Self.costColor)
        } else {
            Text("\(tokenText) / \(costText)")
        }
    }

    private var tokenText: Text {
        Text(formatCodingUsageTokens(counts.totalTokens))
            .fontWeight(.regular)
            .foregroundColor(.secondary)
    }

    private var costText: Text {
        Text(formatCodingUsageCost(counts.costUSD))
            .fontWeight(.semibold)
            .foregroundColor(counts.hasUsage ? Self.costColor : Color(nsColor: .tertiaryLabelColor))
    }

    private static let costColor = Color(nsColor: .textColor)
}
