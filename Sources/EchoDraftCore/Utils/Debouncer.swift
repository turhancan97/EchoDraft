import Foundation

/// Debounces work on the main actor (~400ms). Call ``schedule(_:)`` with the action each time input changes.
@MainActor
public final class Debouncer {
    private var task: Task<Void, Never>?
    private let nanoseconds: UInt64

    public init(nanoseconds: UInt64 = 400_000_000) {
        self.nanoseconds = nanoseconds
    }

    public func schedule(_ action: @escaping () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
