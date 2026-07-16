import Foundation

/// Repeats an async action on a fixed interval (5 min Poll per SPEC-010) until stopped.
@MainActor
final class PollLoop {
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    /// Set after `init` — this indirection lets `AppCoordinator` build its `PollLoop` before
    /// it can capture `self` in the poll closure.
    var onPoll: (() async -> Void)?

    init(interval: TimeInterval = 300) {
        self.interval = interval
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.onPoll?()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
