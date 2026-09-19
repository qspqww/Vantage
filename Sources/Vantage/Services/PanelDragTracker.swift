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
    private(set) var isDragging = false
    private var lastCursorScreen = NSPoint.zero

    /// Records the screen-space cursor position at mouse-down.
    mutating func begin(mouseLocationInWindow: NSPoint, windowOrigin: NSPoint) {
        lastCursorScreen = NSPoint(
            x: windowOrigin.x + mouseLocationInWindow.x,
            y: windowOrigin.y + mouseLocationInWindow.y
        )
        isDragging = true
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
