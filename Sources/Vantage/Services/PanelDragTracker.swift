import Foundation

/// Pure geometry for panel self-dragging, unit-testable without AppKit windows.
///
/// macOS 27 regression: `isMovableByWindowBackground` no longer moves windows
/// whose contentView is an `NSHostingView` (mouse events still arrive, only the
/// automatic move is gone). Panels therefore move themselves by tracking the
/// screen-space cursor and applying its delta to the window origin.
///
/// Uses delta mode because `NSEvent.locationInWindow` is relative to the
/// window's CURRENT frame — after `setFrameOrigin` the hosting view recomputes
/// coordinates, so a fixed grab offset in window space would double-count the
/// movement.
struct PanelDragTracker {
    /// Displacement (points) from mouse-down beyond which a gesture counts as a
    /// drag, not a click. OverlayPanel uses this to swallow the mouse-up so the
    /// hosted SwiftUI button never sees a click at the end of a panel move.
    static let clickThreshold: Double = 5

    private(set) var isDragging = false
    /// True once the cursor has moved at least `clickThreshold` from mouse-down.
    private(set) var movedBeyondClickThreshold = false
    private var downCursorScreen = NSPoint.zero
    private var lastCursorScreen = NSPoint.zero

    /// Records the screen-space cursor position at mouse-down.
    mutating func begin(mouseLocationInWindow: NSPoint, windowOrigin: NSPoint) {
        let cursor = NSPoint(
            x: windowOrigin.x + mouseLocationInWindow.x,
            y: windowOrigin.y + mouseLocationInWindow.y
        )
        downCursorScreen = cursor
        lastCursorScreen = cursor
        isDragging = true
        movedBeyondClickThreshold = false
    }

    /// Applies the screen-space cursor delta to the window origin.
    /// Returns `nil` when not dragging or the cursor did not move.
    mutating func dragged(
        mouseLocationInWindow: NSPoint,
        currentOrigin: NSPoint
    ) -> NSPoint? {
        guard isDragging else { return nil }
        let cursorScreen = NSPoint(
            x: currentOrigin.x + mouseLocationInWindow.x,
            y: currentOrigin.y + mouseLocationInWindow.y
        )
        if !movedBeyondClickThreshold,
           hypot(cursorScreen.x - downCursorScreen.x, cursorScreen.y - downCursorScreen.y)
            >= Self.clickThreshold {
            movedBeyondClickThreshold = true
        }
        let deltaX = cursorScreen.x - lastCursorScreen.x
        let deltaY = cursorScreen.y - lastCursorScreen.y
        lastCursorScreen = cursorScreen
        if deltaX == 0, deltaY == 0 { return nil }
        return NSPoint(x: currentOrigin.x + deltaX, y: currentOrigin.y + deltaY)
    }

    mutating func end() {
        isDragging = false
        lastCursorScreen = .zero
    }
}
