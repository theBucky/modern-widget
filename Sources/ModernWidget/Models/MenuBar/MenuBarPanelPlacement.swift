import CoreGraphics

struct MenuBarPanelPlacement {
    let origin: CGPoint

    init(
        contentSize: CGSize,
        statusItemFrame: CGRect,
        visibleFrame: CGRect,
        spacing: CGFloat
    ) {
        let minX = visibleFrame.minX + spacing
        let maxX = max(minX, visibleFrame.maxX - contentSize.width - spacing)
        let centeredX = statusItemFrame.midX - contentSize.width / 2
        let clampedX = min(max(centeredX, minX), maxX)
        let proposedY = statusItemFrame.minY - contentSize.height - spacing
        let clampedY = max(proposedY, visibleFrame.minY + spacing)

        origin = CGPoint(
            x: clampedX,
            y: clampedY
        )
    }
}
