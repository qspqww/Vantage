import XCTest
@testable import Vantage

final class PreviewGridLayoutTests: XCTestCase {
    private func solve(
        width: CGFloat,
        height: CGFloat,
        count: Int,
        aspect: CGFloat = 16.0 / 9.0
    ) -> PreviewGridLayout {
        PreviewGridSolver.solve(
            width: width,
            height: height,
            count: count,
            minAspect: aspect
        )
    }

    func testSixClientsFillVisibleHeightWithoutScroll() {
        // 1320pt window minus 224pt sidebar ≈ 1096pt workspace, ~600pt tall:
        // the old fixed-250 grid needed scrolling for 6 clients. The solver
        // must pick the largest cards that fit all six on screen.
        let layout = solve(width: 1124, height: 600, count: 6)
        XCTAssertEqual(layout.columnCount, 3)
        XCTAssertEqual(layout.rowCount, 2)
        XCTAssertEqual(layout.cardWidth, 357, accuracy: 1)
        XCTAssertTrue(CGFloat(layout.rowCount) * (layout.cardWidth / (16.0 / 9.0) + PreviewGridSolver.footerHeight) <= 572 + 1)
    }

    func testTwoClientsGrowToMaxCardWidth() {
        // Ample space: two clients share the width instead of sitting at the
        // preferred 250pt with the rest of the row empty.
        let layout = solve(width: 1124, height: 600, count: 2)
        XCTAssertEqual(layout.columnCount, 2)
        XCTAssertEqual(layout.rowCount, 1)
        XCTAssertEqual(layout.cardWidth, PreviewGridSolver.maxCardWidth, accuracy: 1)
    }

    func testManyClientsShortWindowFallsBackToScrolling() {
        // Twelve clients in a short window: even minimum-width cards cannot
        // fit, so fall back to preferred-width columns and let the scroll
        // view handle the overflow.
        let layout = solve(width: 1124, height: 400, count: 12)
        XCTAssertEqual(layout.columnCount, 4)
        XCTAssertEqual(layout.rowCount, 3)
        XCTAssertEqual(layout.cardWidth, PreviewGridSolver.preferredCardWidth, accuracy: 1)
    }

    func testSquareWindowsNeedMoreColumns() {
        // 1:1 windows make rows twice as tall; the solver compensates by
        // adding columns rather than overflowing.
        let layout = solve(width: 1124, height: 900, count: 4, aspect: 1)
        XCTAssertEqual(layout.columnCount, 3)
        XCTAssertEqual(layout.rowCount, 2)
        let rowHeight = layout.cardWidth + PreviewGridSolver.footerHeight
        XCTAssertTrue(CGFloat(layout.rowCount) * rowHeight + layout.gap <= 872 + 1)
    }

    func testEmptyWorkspaceProducesZeroRows() {
        let layout = solve(width: 1124, height: 600, count: 0)
        XCTAssertEqual(layout.rowCount, 0)
        XCTAssertEqual(layout.columnCount, 1)
    }

    func testMixedAspectsUseTallestForFitGuarantee() {
        // One square window among 16:9 ones: every card is at most
        // cardWidth/1 + footer tall, so estimating with the smallest ratio
        // (tallest card) must guarantee the whole grid fits.
        let layout = solve(width: 1124, height: 900, count: 6, aspect: 1)
        let tallestRow = layout.cardWidth + PreviewGridSolver.footerHeight
        let totalHeight = CGFloat(layout.rowCount) * tallestRow + CGFloat(layout.rowCount - 1) * layout.gap
        XCTAssertLessThanOrEqual(totalHeight, 900 - PreviewGridSolver.padding * 2)
    }

    func testCardHeightMatchesQuantizedAspect() {
        // 1549/1000 = 1.549 quantizes to 25/16 = 1.5625; the pinned frame
        // height must be computed from the same quantized value the card
        // renders with, or slack pixels reappear between rows.
        var window = CapturedWindow(
            id: 1,
            processIdentifier: 101,
            ownerName: "EVE Online",
            bundleIdentifier: "com.ccpgames.eve",
            title: "Alice",
            frame: CGRect(x: 0, y: 0, width: 1549, height: 1000),
            instanceOrdinal: 0,
            preview: nil
        )
        XCTAssertEqual(window.displayAspectRatio, 1.5625, accuracy: 0.001)
        let height = PreviewGridSolver.cardHeight(cardWidth: 300, aspect: window.displayAspectRatio)
        XCTAssertEqual(height, 300 / 1.5625 + PreviewGridSolver.footerHeight, accuracy: 0.001)

        window = CapturedWindow(
            id: 2,
            processIdentifier: 101,
            ownerName: "EVE Online",
            bundleIdentifier: "com.ccpgames.eve",
            title: "Bob",
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            instanceOrdinal: 0,
            preview: nil
        )
        // 16:9 quantizes DOWN to 1.75 (28/16) — the quantization the card's
        // aspectRatio modifier also applies.
        XCTAssertEqual(window.displayAspectRatio, 1.75, accuracy: 0.001)
    }
}
