import CoreGraphics
import Testing

@testable import ModernWidget

@Suite("Menu bar panel placement")
struct MenuBarPanelPlacementTests {
    @Test("panel attaches below a centered status item when there is room")
    func panelAttachesBelowCenteredStatusItem() {
        let contentSize = CGSize(width: 60, height: 100)
        let statusItemFrame = CGRect(x: 100, y: 500, width: 20, height: 22)
        let spacing: CGFloat = 6

        let origin = MenuBarPanelPlacement.origin(
            contentSize: contentSize,
            statusItemFrame: statusItemFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 600),
            spacing: spacing
        )
        let panelFrame = CGRect(origin: origin, size: contentSize)

        #expect(abs(panelFrame.midX - statusItemFrame.midX) < 0.0001)
        #expect(abs(panelFrame.maxY - (statusItemFrame.minY - spacing)) < 0.0001)
    }

    @Test("panel stays inside the horizontal visible area")
    func panelStaysInsideHorizontalVisibleArea() {
        let contentSize = CGSize(width: 100, height: 100)
        let visibleFrame = CGRect(x: 0, y: 0, width: 300, height: 600)
        let spacing: CGFloat = 6
        let statusItemFrames = [
            CGRect(x: 0, y: 500, width: 10, height: 22),
            CGRect(x: 260, y: 500, width: 20, height: 22),
        ]

        for statusItemFrame in statusItemFrames {
            let origin = MenuBarPanelPlacement.origin(
                contentSize: contentSize,
                statusItemFrame: statusItemFrame,
                visibleFrame: visibleFrame,
                spacing: spacing
            )
            let panelFrame = CGRect(origin: origin, size: contentSize)

            #expect(panelFrame.minX >= visibleFrame.minX + spacing)
            #expect(panelFrame.maxX <= visibleFrame.maxX - spacing)
        }
    }

    @Test("panel stays above the visible bottom edge")
    func panelStaysAboveVisibleBottomEdge() {
        let contentSize = CGSize(width: 60, height: 580)
        let visibleFrame = CGRect(x: 0, y: 0, width: 300, height: 600)
        let spacing: CGFloat = 6

        let origin = MenuBarPanelPlacement.origin(
            contentSize: contentSize,
            statusItemFrame: CGRect(x: 100, y: 500, width: 20, height: 22),
            visibleFrame: visibleFrame,
            spacing: spacing
        )
        let panelFrame = CGRect(origin: origin, size: contentSize)

        #expect(panelFrame.minY >= visibleFrame.minY + spacing)
    }

    @Test("panel respects a nonzero visible frame origin")
    func panelRespectsNonzeroVisibleFrameOrigin() {
        let contentSize = CGSize(width: 160, height: 180)
        let visibleFrame = CGRect(x: 100, y: 200, width: 400, height: 500)
        let spacing: CGFloat = 8

        let origin = MenuBarPanelPlacement.origin(
            contentSize: contentSize,
            statusItemFrame: CGRect(x: 120, y: 620, width: 20, height: 22),
            visibleFrame: visibleFrame,
            spacing: spacing
        )
        let panelFrame = CGRect(origin: origin, size: contentSize)

        #expect(panelFrame.minX >= visibleFrame.minX + spacing)
        #expect(panelFrame.maxX <= visibleFrame.maxX - spacing)
        #expect(panelFrame.minY >= visibleFrame.minY + spacing)
    }
}
