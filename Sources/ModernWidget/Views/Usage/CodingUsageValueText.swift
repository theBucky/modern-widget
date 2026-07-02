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
                Text(formatCodingUsageTokens(counts.totalTokens))
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
                Text("/")
                    .fontWeight(.regular)
                    .foregroundStyle(Color.secondary)
                Text(formatCodingUsageCost(counts.costUSD))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
        }
    }
}
