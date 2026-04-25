import SwiftUI

struct MenuBarIconView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        let snapshot = viewModel.snapshot

        Group {
            switch snapshot.phase {
            case .paused:
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .symbolEffect(.bounce.down, options: .nonRepeating, value: snapshot.phase)
            case .countingDown, .overdue:
                ProgressRing(
                    progress: snapshot.progress,
                    secondsRemaining: snapshot.secondsRemaining,
                    phase: snapshot.phase
                )
                .frame(width: ProgressRing.size, height: ProgressRing.size)
            }
        }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .animation(.smooth(duration: 0.22), value: snapshot.phase)
    }
}
