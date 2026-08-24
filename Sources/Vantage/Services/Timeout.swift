import Foundation

struct TimeoutError: Error, Equatable {}

/// Generic timeout wrapper: `operation` must be cancellable, throws `TimeoutError` on expiry.
func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        group.cancelAll()
        return result
    }
}

func withTimeout<T: Sendable>(
    milliseconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withTimeout(.milliseconds(milliseconds), operation: operation)
}
