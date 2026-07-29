import Foundation

private let codingUsageFormatLocale = Locale(identifier: "en_US_POSIX")

private func codingUsageFormat(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: format, locale: codingUsageFormatLocale, arguments: arguments)
}

struct CodingUsageDayFormat: FormatStyle, Codable, Hashable, Sendable {
    var timeZone: TimeZone = LocalDay.calendar.timeZone

    func format(_ value: Date) -> String {
        Date.ISO8601FormatStyle(timeZone: timeZone)
            .year().month().day()
            .format(value)
    }
}

struct CodingUsageCostFormat: FormatStyle, Codable, Hashable, Sendable {
    func format(_ value: Double) -> String {
        if value <= 0 {
            return "$0.00"
        }
        if value < 0.01 {
            return codingUsageFormat("$%.4f", value)
        }

        // Narrowest precision that keeps the amount within six characters, so the 32pt
        // cost text fits the detail pane without scaling or truncation.
        let cents = codingUsageFormat("$%.2f", value)
        if cents.count <= 6 {
            return cents
        }
        let tenths = codingUsageFormat("$%.1f", value)
        if tenths.count <= 6 {
            return tenths
        }
        return codingUsageFormat("$%.0f", value)
    }
}

struct CodingUsageTokenFormat: FormatStyle, Codable, Hashable, Sendable {
    func format(_ value: UInt64) -> String {
        let units: [(threshold: Double, suffix: String)] = [
            (1_000_000_000_000, "T"),
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K"),
        ]
        let tokens = Double(value)

        for index in units.indices where tokens >= units[index].threshold {
            // A value like 999,950 rounds to "1000.0K"; display it one unit up as "1.0M".
            let roundsPastUnit =
                index > units.startIndex
                && (tokens / units[index].threshold * 10).rounded() / 10 >= 1000
            let unitIndex = roundsPastUnit ? index - 1 : index
            return codingUsageFormat(
                "%.1f%@ tokens",
                tokens / units[unitIndex].threshold,
                units[unitIndex].suffix
            )
        }

        return codingUsageFormat("%.1f tokens", tokens)
    }
}

struct CodingUsageCostTrendPercentFormat: FormatStyle, Codable, Hashable, Sendable {
    func format(_ value: CodingUsageCostTrend) -> String {
        let percentFormat = FloatingPointFormatStyle<Double>.Percent.percent
            .precision(.fractionLength(1))
            .sign(strategy: .always(includingZero: false))
            .locale(codingUsageFormatLocale)

        return (value.percent / 100).formatted(percentFormat)
    }
}

extension FormatStyle where Self == CodingUsageDayFormat {
    static var codingUsageDay: Self { Self() }
}

extension FormatStyle where Self == CodingUsageCostFormat {
    static var codingUsageCost: Self { Self() }
}

extension FormatStyle where Self == CodingUsageTokenFormat {
    static var codingUsageTokens: Self { Self() }
}

extension FormatStyle where Self == CodingUsageCostTrendPercentFormat {
    static var codingUsageCostTrendPercent: Self { Self() }
}
