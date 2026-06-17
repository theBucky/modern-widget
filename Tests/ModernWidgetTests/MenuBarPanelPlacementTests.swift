import CoreGraphics
import Testing

@testable import ModernWidget

@Suite("Menu bar panel placement")
struct MenuBarPanelPlacementTests {
    @Test("panel centers under the status item")
    func centeredPlacement() {
        let origin = MenuBarPanelPlacement.origin(
            contentSize: CGSize(width: 60, height: 100),
            statusItemFrame: CGRect(x: 100, y: 500, width: 20, height: 22),
            visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 600),
            spacing: 6
        )

        #expect(origin == CGPoint(x: 80, y: 394))
    }

    @Test("panel clamps to visible frame")
    func clampedPlacement() {
        let origin = MenuBarPanelPlacement.origin(
            contentSize: CGSize(width: 100, height: 100),
            statusItemFrame: CGRect(x: 0, y: 500, width: 10, height: 22),
            visibleFrame: CGRect(x: 0, y: 0, width: 80, height: 600),
            spacing: 6
        )

        #expect(origin == CGPoint(x: 6, y: 394))
    }

    @Test("panel clamps inside the visible right edge")
    func rightClampedPlacement() {
        let origin = MenuBarPanelPlacement.origin(
            contentSize: CGSize(width: 100, height: 100),
            statusItemFrame: CGRect(x: 260, y: 500, width: 20, height: 22),
            visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 600),
            spacing: 6
        )

        #expect(origin == CGPoint(x: 194, y: 394))
    }

    @Test("panel clamps above the visible bottom edge")
    func verticalClampedPlacement() {
        let origin = MenuBarPanelPlacement.origin(
            contentSize: CGSize(width: 60, height: 580),
            statusItemFrame: CGRect(x: 100, y: 500, width: 20, height: 22),
            visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 600),
            spacing: 6
        )

        #expect(origin == CGPoint(x: 80, y: 6))
    }
}
