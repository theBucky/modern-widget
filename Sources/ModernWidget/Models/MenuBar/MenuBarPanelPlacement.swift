import CoreGraphics

struct MenuBarPanelPlacement: Equatable {
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

        origin = CGPoint(
            x: clampedX,
            y: statusItemFrame.minY - contentSize.height - spacing
        )
    }
}
