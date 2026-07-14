import Foundation
import Testing

@testable import ModernWidget

@Suite("Walk history day display")
struct WalkHistoryDayDisplayTests {
    private static let now = date(2026, 7, 15, 12)

    private func makeDisplay(
        _ day: Date,
        walkCount: Int = 0,
        isSupplementTaken: Bool = false
    ) -> WalkHistoryDayDisplay {
        WalkHistoryDayDisplay(
            date: day,
            walkCount: walkCount,
            isSupplementTaken: isSupplementTaken,
            now: Self.now,
            calendar: gregorianUTC()
        )
    }

    @Test("tomorrow dims as future with no fill")
    func tomorrowIsFuture() {
        let display = makeDisplay(date(2026, 7, 16))

        #expect(display.label == .future)
        #expect(display.fill == .empty)
    }

    @Test("a later hour today is not future")
    func laterHourTodayIsNotFuture() {
        #expect(makeDisplay(date(2026, 7, 15, 23)).label == .supplementPending)
    }

    @Test("past days read supplement state")
    func pastDaySupplementState() {
        #expect(makeDisplay(date(2026, 7, 14), isSupplementTaken: true).label == .supplementTaken)
        #expect(makeDisplay(date(2026, 7, 14)).label == .supplementPending)
    }

    @Test("today fill wins over walked fill")
    func todayFillWins() {
        #expect(makeDisplay(date(2026, 7, 15), walkCount: 2).fill == .today)
    }

    @Test("walked past days fill, empty ones do not")
    func walkedFill() {
        #expect(makeDisplay(date(2026, 7, 14), walkCount: 1).fill == .walked)
        #expect(makeDisplay(date(2026, 7, 14)).fill == .empty)
    }
}
