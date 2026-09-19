import XCTest
@testable import Vantage

final class PanelDragTrackerTests: XCTestCase {
    func testDragAppliesCursorDeltaToOrigin() {
        var tracker = PanelDragTracker()
        // Grab at window (100,50); cursor sits at screen (130,70).
        tracker.begin(mouseLocationInWindow: NSPoint(x: 30, y: 20), windowOrigin: NSPoint(x: 100, y: 50))

        // Physically move the cursor +30/+20; window still at the old origin,
        // so the event reports cursorInWindow (60,40).
        let moved = tracker.dragged(mouseLocationInWindow: NSPoint(x: 60, y: 40), currentOrigin: NSPoint(x: 100, y: 50))
        XCTAssertEqual(moved?.x, 130)
        XCTAssertEqual(moved?.y, 70)
    }

    func testMultipleDragEventsFollowPhysicalCursor() {
        var tracker = PanelDragTracker()
        tracker.begin(mouseLocationInWindow: NSPoint(x: 10, y: 10), windowOrigin: NSPoint(x: 0, y: 0))
        // Cursor screen (10,10) at grab.

        // Physical move +10/+15 → cursor screen (20,25); window origin (0,0).
        let first = tracker.dragged(mouseLocationInWindow: NSPoint(x: 20, y: 25), currentOrigin: NSPoint(x: 0, y: 0))
        XCTAssertEqual(first?.x, 10)
        XCTAssertEqual(first?.y, 15)

        // Window has moved to (10,15). Another physical +10/+5 puts the cursor
        // at screen (30,30) → locationInWindow becomes (20,15).
        let second = tracker.dragged(mouseLocationInWindow: NSPoint(x: 20, y: 15), currentOrigin: NSPoint(x: 10, y: 15))
        XCTAssertEqual(second?.x, 20)
        XCTAssertEqual(second?.y, 20)
    }

    func testNoCursorMovementReturnsNil() {
        var tracker = PanelDragTracker()
        tracker.begin(mouseLocationInWindow: NSPoint(x: 5, y: 5), windowOrigin: NSPoint(x: 40, y: 40))
        // Cursor physically still: with the window already moved by the OS delta
        // to (40,40), locationInWindow is unchanged → delta zero → nil.
        XCTAssertNil(tracker.dragged(mouseLocationInWindow: NSPoint(x: 5, y: 5), currentOrigin: NSPoint(x: 40, y: 40)))
    }

    func testDraggedBeforeBeginReturnsNil() {
        var tracker = PanelDragTracker()
        XCTAssertNil(tracker.dragged(mouseLocationInWindow: NSPoint(x: 5, y: 5), currentOrigin: NSPoint(x: 0, y: 0)))
    }

    func testEndStopsDragging() {
        var tracker = PanelDragTracker()
        tracker.begin(mouseLocationInWindow: .zero, windowOrigin: .zero)
        tracker.end()
        XCTAssertFalse(tracker.isDragging)
        XCTAssertNil(tracker.dragged(mouseLocationInWindow: NSPoint(x: 5, y: 5), currentOrigin: NSPoint(x: 0, y: 0)))
    }
}
