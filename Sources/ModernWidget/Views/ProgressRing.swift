import SwiftUI

struct ProgressRing: View {
    static let size: CGFloat = 18
    static let lineWidth: CGFloat = 2.25
    static let alertThreshold: Double = 0.15

    private static let solidStroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
    private static let outerPadding: CGFloat = lineWidth / 2 + 1

    let progress: Double
    let phase: ReminderPhase

    var body: some View {
        Group {
            if phase == .overdue {
                Circle().stroke(.red, style: Self.solidStroke)
            } else {
                ZStack {
                    Circle().stroke(tint.opacity(0.25), lineWidth: Self.lineWidth)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(tint, style: Self.solidStroke)
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .padding(Self.outerPadding)
    }

    private var tint: Color {
        progress < Self.alertThreshold ? .orange : .primary
    }
}
