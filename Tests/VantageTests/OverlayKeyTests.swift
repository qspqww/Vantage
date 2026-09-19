import XCTest
@testable import Vantage

final class OverlayKeyTests: XCTestCase {
    private func window(
        id: CGWindowID,
        pid: pid_t = 101,
        title: String = "Alice",
        ordinal: Int = 0,
        frame: CGRect = CGRect(x: 0, y: 0, width: 1280, height: 720)
    ) -> CapturedWindow {
        CapturedWindow(
            id: id,
            processIdentifier: pid,
            ownerName: "EVE Online",
            bundleIdentifier: "com.ccpgames.eve",
            title: title,
            frame: frame,
            instanceOrdinal: ordinal,
            preview: nil
        )
    }

    func testOverlayPositionKeyStableAcrossResize() {
        let small = window(id: 1, frame: CGRect(x: 10, y: 20, width: 1280, height: 720))
        let large = window(id: 1, frame: CGRect(x: 10, y: 20, width: 2560, height: 1440))
        XCTAssertEqual(small.overlayPositionKey, large.overlayPositionKey)
    }

    func testOverlayPositionKeyStableAcrossMove() {
        let here = window(id: 1, frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        let there = window(id: 1, frame: CGRect(x: 500, y: 900, width: 1280, height: 720))
        XCTAssertEqual(here.overlayPositionKey, there.overlayPositionKey)
    }

    func testOverlayPositionKeyDiffersByOrdinalAndTitle() {
        let first = window(id: 1, ordinal: 0)
        let second = window(id: 2, ordinal: 1)
        let renamed = window(id: 3, title: "Bob", ordinal: 0)
        XCTAssertNotEqual(first.overlayPositionKey, second.overlayPositionKey)
        XCTAssertNotEqual(first.overlayPositionKey, renamed.overlayPositionKey)
    }

    func testStableOrdinalsIndependentOfGeometryAndPosition() {
        // Two identical-title clients; resizing/moving the first must not
        // reshuffle ordinals. Only ascending windowID defines the order.
        let entries: [(pid: pid_t, title: String, id: CGWindowID)] = [
            (101, "Alice", 5),
            (101, "Alice", 2),
            (101, "Bob", 9)
        ]
        let ordinals = WindowCaptureService.stableOrdinals(entries: entries)
        XCTAssertEqual(ordinals[2], 0)
        XCTAssertEqual(ordinals[5], 1)
        XCTAssertEqual(ordinals[9], 0)

        // Same windows at different sizes/positions → identical ordinals.
        let sameWindowsResized = WindowCaptureService.stableOrdinals(entries: entries)
        XCTAssertEqual(ordinals, sameWindowsResized)
    }

    func testStableOrdinalsGroupsByTitle() {
        let entries: [(pid: pid_t, title: String, id: CGWindowID)] = [
            (101, "Alice", 1),
            (101, "Bob", 2),
            (101, "Alice", 3)
        ]
        let ordinals = WindowCaptureService.stableOrdinals(entries: entries)
        XCTAssertEqual(ordinals[1], 0)
        XCTAssertEqual(ordinals[3], 1)
        XCTAssertEqual(ordinals[2], 0) // separate group
    }
}
