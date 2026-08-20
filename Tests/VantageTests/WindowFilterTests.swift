import XCTest
@testable import Vantage

final class WindowFilterTests: XCTestCase {
    func testExactOwnerNameMatches() {
        XCTAssertTrue(WindowFilter.isEligible(
            ownerName: "eve online",
            bundleIdentifier: "com.ccpgames.eve",
            exactBundleIdentifiers: [],
            exactOwnerNames: ["EVE Online"]
        ))

        XCTAssertTrue(WindowFilter.isEligible(
            ownerName: "EVE Online",
            bundleIdentifier: "com.ccpgames.eve",
            exactBundleIdentifiers: [],
            exactOwnerNames: ["EVE Online"]
        ))
    }

    func testPartialOwnerNameDoesNotMatch() {
        XCTAssertFalse(WindowFilter.isEligible(
            ownerName: "EVE Online Helper",
            bundleIdentifier: "com.ccpgames.eve.helper",
            exactBundleIdentifiers: ["com.ccpgames.eve"],
            exactOwnerNames: ["EVE Online"]
        ))
    }

    func testExactBundleIdentifierMatchesAndPrefixDoesNot() {
        XCTAssertTrue(WindowFilter.isEligible(
            ownerName: "Wrapped Client",
            bundleIdentifier: "com.example.eve",
            exactBundleIdentifiers: ["com.example.eve"],
            exactOwnerNames: []
        ))

        XCTAssertFalse(WindowFilter.isEligible(
            ownerName: "Wrapped Client",
            bundleIdentifier: "com.example.eve.helper",
            exactBundleIdentifiers: ["com.example.eve"],
            exactOwnerNames: []
        ))
    }

    func testExactApplicationIdentityRemainsRequired() {
        XCTAssertFalse(WindowFilter.isEligible(
            ownerName: "Window Server",
            bundleIdentifier: nil,
            exactBundleIdentifiers: [],
            exactOwnerNames: []
        ))

        XCTAssertTrue(WindowFilter.isEligible(
            ownerName: "EVE Online",
            bundleIdentifier: "com.ccpgames.eve",
            exactBundleIdentifiers: [],
            exactOwnerNames: ["EVE Online"]
        ))

        XCTAssertFalse(WindowFilter.isEligible(
            ownerName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            exactBundleIdentifiers: [],
            exactOwnerNames: ["EVE Online"]
        ))
    }

    func testNormalWindowRejectsIrrelevantLayersAndEmptyTitles() {
        XCTAssertTrue(WindowFilter.isNormalWindow(
            isOnScreen: true,
            windowLayer: 0,
            title: "EVE Online",
            frame: CGRect(x: 0, y: 0, width: 1280, height: 720)
        ))

        XCTAssertFalse(WindowFilter.isNormalWindow(
            isOnScreen: true,
            windowLayer: 1,
            title: "EVE Online",
            frame: CGRect(x: 0, y: 0, width: 1280, height: 720)
        ))

        XCTAssertFalse(WindowFilter.isNormalWindow(
            isOnScreen: true,
            windowLayer: 0,
            title: "",
            frame: CGRect(x: 0, y: 0, width: 1280, height: 720)
        ))
    }
}
