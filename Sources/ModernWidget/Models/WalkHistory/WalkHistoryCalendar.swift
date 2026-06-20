import Foundation

struct WalkHistoryMonth {
    let month: Date
    let dayCells: [Date?]

    init(containing date: Date, calendar: Calendar = .current) {
        let firstDay = calendar.startOfMonth(for: date)
        let dayCount = calendar.range(of: .day, in: .month, for: firstDay)!.count
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let filledCells = leadingBlanks + dayCount
        let cellCount = filledCells + (7 - filledCells % 7) % 7

        month = firstDay
        dayCells = (0..<cellCount).map { cellIndex in
            let dayOffset = cellIndex - leadingBlanks
            guard (0..<dayCount).contains(dayOffset) else { return nil }
            return calendar.date(byAdding: .day, value: dayOffset, to: firstDay)!
        }
    }
}

enum WalkHistoryCalendar {
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }
}
