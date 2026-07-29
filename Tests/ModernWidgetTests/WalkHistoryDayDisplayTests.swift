import Foundation
import Testing

@testable import ModernWidget

@Suite("Walk history day display")
struct WalkHistoryDayDisplayTests {
    private static let today = LocalDay(year: 2026, month: 7, day: 15)!

    private func makeDisplay(
        _ day: LocalDay?,
        walkCount: Int = 0,
        isSupplementTaken: Bool = false
    ) -> WalkHistoryDayDisplay {
        WalkHistoryDayDisplay(
            day: day!,
            today: Self.today,
            walkCount: walkCount,
            isSupplementTaken: isSupplementTaken
        )
    }

    @Test("tomorrow dims as future with no fill")
    func tomorrowIsFuture() {
        let display = makeDisplay(LocalDay(year: 2026, month: 7, day: 16))

        #expect(display.label == .future)
        #expect(display.fill == .empty)
    }

    @Test("today reads supplement state instead of dimming as future")
    func todayIsNotFuture() {
        #expect(makeDisplay(Self.today).label == .supplementPending)
    }

    @Test("past days read supplement state")
    func pastDaySupplementState() {
        let yesterday = LocalDay(year: 2026, month: 7, day: 14)

        #expect(makeDisplay(yesterday, isSupplementTaken: true).label == .supplementTaken)
        #expect(makeDisplay(yesterday).label == .supplementPending)
    }

    @Test("today fill wins over walked fill")
    func todayFillWins() {
        #expect(makeDisplay(Self.today, walkCount: 2).fill == .today)
    }

    @Test("walked past days fill, empty ones do not")
    func walkedFill() {
        let yesterday = LocalDay(year: 2026, month: 7, day: 14)

        #expect(makeDisplay(yesterday, walkCount: 1).fill == .walked)
        #expect(makeDisplay(yesterday).fill == .empty)
    }
}
