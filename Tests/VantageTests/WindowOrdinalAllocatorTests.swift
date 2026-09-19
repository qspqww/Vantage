import XCTest
@testable import Vantage

final class WindowOrdinalAllocatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func entries(
        _ list: [(pid_t, String, CGWindowID)]
    ) -> [(pid: pid_t, title: String, id: CGWindowID)] {
        list.map { (pid: $0.0, title: $0.1, id: $0.2) }
    }

    func testFreshGroupAssignsAscendingIDsAscendingOrdinals() {
        var allocator = WindowOrdinalAllocator()
        let ordinals = allocator.assign(
            entries: entries([(101, "Alice", 5), (101, "Alice", 2), (101, "Bob", 9)]),
            now: t0
        )
        XCTAssertEqual(ordinals[2], 0)
        XCTAssertEqual(ordinals[5], 1)
        XCTAssertEqual(ordinals[9], 0) // separate title group
    }

    func testTransientDropoutDoesNotReshuffleSurvivor() {
        var allocator = WindowOrdinalAllocator()
        _ = allocator.assign(entries: entries([(101, "Alice", 100), (101, "Alice", 200)]), now: t0)

        // Window 100 vanishes for one cycle: 200 must keep ordinal 1, not
        // collapse to 0 — otherwise its overlay position key changes and the
        // panel jumps to window 100's remembered spot.
        let duringGap = allocator.assign(entries: entries([(101, "Alice", 200)]), now: t0 + 0.25)
        XCTAssertEqual(duringGap[200], 1)

        let afterReturn = allocator.assign(
            entries: entries([(101, "Alice", 100), (101, "Alice", 200)]),
            now: t0 + 0.5
        )
        XCTAssertEqual(afterReturn[100], 0)
        XCTAssertEqual(afterReturn[200], 1)
    }

    func testRecreatedWindowReclaimsTombstoneOrdinal() {
        var allocator = WindowOrdinalAllocator()
        _ = allocator.assign(entries: entries([(101, "Alice", 100), (101, "Alice", 200)]), now: t0)

        // Fullscreen toggle: window 100 destroyed, recreated as 300.
        _ = allocator.assign(entries: entries([(101, "Alice", 200)]), now: t0 + 0.25)
        let after = allocator.assign(
            entries: entries([(101, "Alice", 200), (101, "Alice", 300)]),
            now: t0 + 0.5
        )
        XCTAssertEqual(after[300], 0, "recreated window reclaims the freed ordinal")
        XCTAssertEqual(after[200], 1)
    }

    func testTombstoneExpiresAfterGrace() {
        var allocator = WindowOrdinalAllocator(graceInterval: 4.0)
        _ = allocator.assign(entries: entries([(101, "Alice", 100), (101, "Alice", 200)]), now: t0)
        _ = allocator.assign(entries: entries([(101, "Alice", 200)]), now: t0 + 0.25)

        // Long after the grace window, a new window no longer reclaims 0's
        // tombstone for identity purposes — it simply takes the lowest free
        // ordinal, which is still 0 since only ordinal 1 is live.
        let after = allocator.assign(
            entries: entries([(101, "Alice", 200), (101, "Alice", 300)]),
            now: t0 + 10
        )
        XCTAssertEqual(after[300], 0)
        XCTAssertEqual(after[200], 1)
    }

    func testVanishedGroupTombstonesSurviveAndExpire() {
        var allocator = WindowOrdinalAllocator(graceInterval: 4.0)
        _ = allocator.assign(entries: entries([(101, "Alice", 100)]), now: t0)

        // Whole group gone, then a window returns within grace: reclaims 0.
        _ = allocator.assign(entries: entries([(101, "Bob", 500)]), now: t0 + 0.25)
        let withinGrace = allocator.assign(entries: entries([(101, "Alice", 300)]), now: t0 + 1)
        XCTAssertEqual(withinGrace[300], 0)
    }

    func testSeparatePidGroupsAreIndependent() {
        var allocator = WindowOrdinalAllocator()
        let ordinals = allocator.assign(
            entries: entries([(101, "Alice", 1), (202, "Alice", 2)]),
            now: t0
        )
        XCTAssertEqual(ordinals[1], 0)
        XCTAssertEqual(ordinals[2], 0)
    }
}
