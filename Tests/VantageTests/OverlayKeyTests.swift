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
}
