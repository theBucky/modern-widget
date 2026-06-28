import SwiftUI

struct MenuBarIconView: View {
    let engine: ReminderEngine

    var body: some View {
        let snapshot = engine.menuBarSnapshot

        Group {
            switch snapshot.phase {
            case .paused:
                Image(systemName: "pause.circle.fill")
            case .countingDown:
                Image(systemName: "clock.circle", variableValue: snapshot.progress)
            case .overdue:
                Image(systemName: "exclamationmark.circle.fill")
            }
        }
        .symbolRenderingMode(.hierarchical)
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.bounce.down, options: .nonRepeating, value: snapshot.phase)
    }
}
