import XCTest
@testable import Vantage

final class DiscoveryTests: XCTestCase {
    private let resolver: (pid_t) -> String? = { pid in
        switch pid {
        case 101: return "com.ccpgames.eve"
        case 102: return "com.example.wrapped"
        default: return nil
        }
    }

    private func fixture(
        id: UInt32 = 1,
        pid: pid_t,
        owner: String,
        title: String?,
        x: Double = 0, y: Double = 0,
        width: Double = 1280, height: Double = 720,
        layer: Int = 0
    ) -> [String: Any] {
        var info: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: id),
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowOwnerName as String: owner,
            kCGWindowBounds as String: [
                "X": x, "Y": y, "Width": width, "Height": height
            ],
            kCGWindowLayer as String: NSNumber(value: layer)
        ]
        if let title { info[kCGWindowName as String] = title }
        return info
    }

    func testParseExtractsAllFields() {
        let window = WindowCaptureService.parseDiscovered(
            fixture(id: 42, pid: 101, owner: "EVE Online", title: "Alice"),
            bundleResolver: resolver
        )
        XCTAssertNotNil(window)
        XCTAssertEqual(window?.windowID, 42)
        XCTAssertEqual(window?.processIdentifier, 101)
        XCTAssertEqual(window?.ownerName, "EVE Online")
        XCTAssertEqual(window?.bundleIdentifier, "com.ccpgames.eve")
        XCTAssertEqual(window?.title, "Alice")
        XCTAssertEqual(window?.frame.width, 1280)
        XCTAssertEqual(window?.frame.height, 720)
    }

    func testParseReturnsNilWithoutBoundsOrID() {
        XCTAssertNil(WindowCaptureService.parseDiscovered(
            [kCGWindowNumber as String: NSNumber(value: 7)],
            bundleResolver: resolver
        ))
        var noBounds = fixture(pid: 101, owner: "EVE Online", title: "t")
        noBounds.removeValue(forKey: kCGWindowBounds as String)
        XCTAssertNil(WindowCaptureService.parseDiscovered(noBounds, bundleResolver: resolver))
    }

    func testNumberAndIntBoundStylesBothParse() {
        // CGWindowList may hand back Int or NSDecimal-typed bounds; both must parse.
        var mixed = fixture(pid: 102, owner: "Wrapped", title: "B")
        var bounds = mixed[kCGWindowBounds as String] as? [String: Any] ?? [:]
        bounds["X"] = 15
        mixed[kCGWindowBounds as String] = bounds
        let window = WindowCaptureService.parseDiscovered(mixed, bundleResolver: resolver)
        XCTAssertEqual(window?.frame.origin.x, 15.0)
    }

    func testDiscoverFiltersRanksAndCaps() {
        let raw = [
            fixture(id: 1, pid: 101, owner: "EVE Online", title: "Charlie"),
            fixture(id: 2, pid: 101, owner: "eve online", title: "alice"),
            fixture(id: 3, pid: 101, owner: "EVE Online", title: "bob"),
            fixture(id: 4, pid: 999, owner: "Safari", title: "Not Allowed"),
            fixture(id: 5, pid: 101, owner: "EVE Online", title: "Small", width: 100, height: 80),
            fixture(id: 6, pid: 101, owner: "EVE Online", title: "", layer: 1)
        ]
        let found = WindowCaptureService.discoverWindows(
            raw: raw,
            bundleResolver: resolver,
            ownerAllowlist: ["EVE Online"],
            bundleAllowlist: []
        )

        // Deterministic order within same owner/title: y then x; title uses
        // case-sensitive compare matching prior SCShareableContent behavior.
        XCTAssertEqual(found.map(\.windowID), [1, 3, 2])
        XCTAssertEqual(found.map(\.title), ["Charlie", "bob", "alice"])
    }

    func testDiscoverCapsAtTwelve() {
        let raw = (1...20).map {
            fixture(id: UInt32($0), pid: 101, owner: "EVE Online",
                    title: String(format: "char-%02d", $0))
        }
        let found = WindowCaptureService.discoverWindows(
            raw: raw,
            bundleResolver: resolver,
            ownerAllowlist: ["EVE Online"],
            bundleAllowlist: []
        )
        XCTAssertEqual(found.count, 12)
    }
}
