import XCTest
@testable import Vantage

final class TimeoutTests: XCTestCase {
    func testReturnsValueBeforeDeadline() async throws {
        let start = Date()
        let value = try await withTimeout(.milliseconds(500)) { 42 }
        XCTAssertEqual(value, 42)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.45)
    }

    func testThrowsAtDeadlineEvenWhenOperationIgnoresCancellation() async {
        let start = Date()
        do {
            _ = try await withTimeout(.milliseconds(150)) {
                // Simulate an un-cancellable blocking C call: swallows
                // cancellation and runs to its own 3s deadline.
                let opDeadline = Date().addingTimeInterval(3)
                while Date() < opDeadline {
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { /* ignored */ }
                }
                return 7
            }
            XCTFail("expected TimeoutError")
        } catch let error as TimeoutError {
            let elapsed = Date().timeIntervalSince(start)
            // Must NOT await the abandoned operation (structured groups would).
            XCTAssertLessThan(elapsed, 1.0, "timeout waited for an un-cancellable operation")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testPropagatesCallerCancellation() async {
        let task = Task {
            try await withTimeout(.seconds(5)) {
                try? await Task.sleep(for: .seconds(5))
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }
}
