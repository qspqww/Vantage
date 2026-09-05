import Foundation

struct TimeoutError: Error, Equatable {}

/// Timeout that actually enforces its deadline for operations which cannot be
/// cancelled cooperatively — blocking C calls such as ScreenCaptureKit
/// `captureImage` on a just-closed window (frame waiter hangs forever) and
/// Accessibility IPC to a dying process.
///
/// WHY NOT `withThrowingTaskGroup`: structured concurrency must await every
/// child before the group scope exits. When the deadline child throws, the
/// scope still blocks on the operation child, and a child stuck inside an
/// un-cancellable C call keeps the caller suspended forever. That was the
/// root cause of "click a stale preview of an exited client → activation
/// fails → every window update freezes": the 800ms capture timeout never
/// returned, so `refresh()` never returned.
///
/// This implementation runs the operation in an UNSTRUCTURED detached task
/// and simply abandons it when the deadline hits. The abandoned task ends
/// whenever the underlying call finally does (or leaks until then) without
/// ever blocking the caller.
/// Thread-safe completion flag; `Task` has no public `isCompleted`, so the
/// operation records completion itself and the poll loop checks the flag.
private final class CompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    var isDone: Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }

    func finish() {
        lock.lock()
        done = true
        lock.unlock()
    }
}

func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let completion = CompletionFlag()
    let operationTask = Task.detached(priority: .userInitiated) {
        defer { completion.finish() }
        return try await operation()
    }
    // Best-effort cancel for cooperatively-cancellable ops; abandoned blocking
    // ops are unaffected and simply finish later with their result discarded.
    defer { operationTask.cancel() }

    let deadline = ContinuousClock.now.advanced(by: duration)
    while ContinuousClock.now < deadline {
        if completion.isDone {
            return try await operationTask.value
        }
        // Propagates CancellationError if the caller is cancelled.
        try await Task.sleep(for: .milliseconds(10))
    }
    throw TimeoutError()
}

func withTimeout<T: Sendable>(
    milliseconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withTimeout(.milliseconds(milliseconds), operation: operation)
}
