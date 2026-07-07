import SwiftUI

struct MenuBarIconView: View {
    let engine: ReminderEngine

    var body: some View {
        let snapshot = engine.currentSnapshot

        Group {
            switch snapshot.phase {
            case .paused:
                Image(systemName: "pause.circle.fill")
            case .countingDown:
                // CoreGraphics' process-wide font cache never evicts, and each distinct
                // variableValue pins fresh glyph bitmaps in it (~40 MB/h at one value per
                // second), so the symbol sees only 64 levels: indistinguishable at menu
                // bar size.
                Image(
                    systemName: "clock.circle",
                    variableValue: (snapshot.progress * 64).rounded() / 64
                )
            case .overdue:
                Image(systemName: "exclamationmark.circle.fill")
            }
        }
        .symbolRenderingMode(.hierarchical)
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.bounce.down, options: .nonRepeating, value: snapshot.phase)
    }
}
