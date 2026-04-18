import Foundation

@MainActor
final class RefreshLoop {
    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }

    func schedule(after delay: TimeInterval?, action: @escaping @MainActor () -> Void) {
        cancel()

        guard let delay else {
            return
        }

        task = Task {
            try? await Task.sleep(for: .seconds(delay))

            guard !Task.isCancelled else {
                return
            }

            action()
        }
    }
}
