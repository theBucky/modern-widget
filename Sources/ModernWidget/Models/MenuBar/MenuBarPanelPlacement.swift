import CoreGraphics

enum MenuBarPanelPlacement {
    static func origin(
        contentSize: CGSize,
        statusItemFrame: CGRect,
        visibleFrame: CGRect,
        spacing: CGFloat
    ) -> CGPoint {
        let frame = visibleFrame.insetBy(dx: spacing, dy: spacing)
        let maxX = max(frame.minX, frame.maxX - contentSize.width)
        let centeredX = statusItemFrame.midX - contentSize.width / 2

        return CGPoint(
            x: min(max(centeredX, frame.minX), maxX),
            y: max(statusItemFrame.minY - contentSize.height - spacing, frame.minY)
        )
    }
}
