import Foundation

func formatCodingUsageCost(_ cost: Double) -> String {
    if cost <= 0 {
        return "$0.00"
    }
    if cost < 0.01 {
        return String(format: "$%.4f", cost)
    }
    return String(format: "$%.2f", cost)
}

func formatCodingUsageTokens(_ tokens: UInt64) -> String {
    let units: [(threshold: Double, suffix: String)] = [
        (1_000_000_000_000, "T"),
        (1_000_000_000, "B"),
        (1_000_000, "M"),
        (1_000, "K"),
    ]
    let value = Double(tokens)

    for unit in units {
        guard value >= unit.threshold else {
            continue
        }
        return String(format: "%.1f%@ tokens", value / unit.threshold, unit.suffix)
    }

    return String(format: "%.1f tokens", value)
}

func formatCodingUsageCostTrendMagnitude(_ trend: CodingUsageCostTrend) -> String {
    String(format: "%.1f%%", abs(trend.percent))
}
