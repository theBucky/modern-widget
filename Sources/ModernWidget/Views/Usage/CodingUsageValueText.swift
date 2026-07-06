import SwiftUI

struct CodingUsageValueText: View {
    let counts: CodingTokenCounts

    var body: some View {
        HStack(spacing: 3) {
            Text(counts.totalTokens, format: .codingUsageTokens)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
            Text(verbatim: "/")
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
            Text(counts.costUSD, format: .codingUsageCost)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }
}
