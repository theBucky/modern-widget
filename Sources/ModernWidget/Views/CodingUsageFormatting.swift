import Foundation

private let codingUsageFormatLocale = Locale(identifier: "en_US_POSIX")

private func codingUsageFormat(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: format, locale: codingUsageFormatLocale, arguments: arguments)
}

func formatCodingUsageCost(_ cost: Double) -> String {
    if cost <= 0 {
        return "$0.00"
    }
    if cost < 0.01 {
        return codingUsageFormat("$%.4f", cost)
    }
    return codingUsageFormat("$%.2f", cost)
}

func formatCodingUsageTokens(_ tokens: UInt64) -> String {
    let units: [(threshold: Double, suffix: String)] = [
        (1_000_000_000_000, "T"),
        (1_000_000_000, "B"),
        (1_000_000, "M"),
        (1_000, "K"),
    ]
    let value = Double(tokens)

    for index in units.indices {
        guard value >= units[index].threshold else {
            continue
        }

        var unitIndex = index
        var unitValue = value / units[unitIndex].threshold
        while unitIndex > units.startIndex && (unitValue * 10).rounded() / 10 >= 1000 {
            unitIndex -= 1
            unitValue = value / units[unitIndex].threshold
        }
        return codingUsageFormat("%.1f%@ tokens", unitValue, units[unitIndex].suffix)
    }

    return codingUsageFormat("%.1f tokens", value)
}

func formatCodingUsageCostTrendPercent(_ trend: CodingUsageCostTrend) -> String {
    let percentFormat = FloatingPointFormatStyle<Double>.Percent.percent
        .precision(.fractionLength(1))
        .sign(strategy: .always(includingZero: false))
        .locale(codingUsageFormatLocale)

    return (trend.percent / 100).formatted(percentFormat)
}
