import Foundation

/// Display projection of one calendar day cell: which label color and fill the walk
/// grid renders, derived from the day's relation to today and its recorded state.
struct WalkHistoryDayDisplay: Equatable {
    enum Label {
        case future
        case supplementTaken
        case supplementPending
    }

    enum Fill {
        case today
        case walked
        case empty
    }

    let label: Label
    let fill: Fill

    init(
        date: Date,
        walkCount: Int,
        isSupplementTaken: Bool,
        now: Date = .now,
        calendar: Calendar = LocalDay.calendar
    ) {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)

        if day > today {
            label = .future
        } else if isSupplementTaken {
            label = .supplementTaken
        } else {
            label = .supplementPending
        }

        if day == today {
            fill = .today
        } else if walkCount > 0 {
            fill = .walked
        } else {
            fill = .empty
        }
    }
}
