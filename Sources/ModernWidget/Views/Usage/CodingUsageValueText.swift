import SwiftUI

struct CodingUsageValueText: View {
    let counts: CodingTokenCounts
    let isLoading: Bool

    var body: some View {
        if isLoading {
            Text("loading")
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 3) {
                tokenText
                Text("/")
                    .fontWeight(.regular)
                    .foregroundStyle(Color.secondary)
                costText
            }
        }
    }

    private var tokenText: some View {
        Text(formatCodingUsageTokens(counts.totalTokens))
            .fontWeight(.regular)
            .foregroundStyle(.secondary)
    }

    private var costText: some View {
        Text(formatCodingUsageCost(counts.costUSD))
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
    }
}
