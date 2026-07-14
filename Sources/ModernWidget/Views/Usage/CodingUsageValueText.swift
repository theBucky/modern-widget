import SwiftUI

struct CodingUsageValueText: View {
    let totals: CodingUsageTotals

    var body: some View {
        HStack(spacing: 3) {
            Text(totals.totalTokens, format: .codingUsageTokens)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
            Text(verbatim: "/")
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
            Text(totals.costUSD, format: .codingUsageCost)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }
}
