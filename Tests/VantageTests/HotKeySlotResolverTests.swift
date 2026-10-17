import XCTest
@testable import Vantage

final class HotKeySlotResolverTests: XCTestCase {
    private func window(
        id: CGWindowID,
        pid: pid_t = 101,
        title: String = "Alice",
        ordinal: Int = 0
    ) -> CapturedWindow {
        CapturedWindow(
            id: id,
            processIdentifier: pid,
            ownerName: "EVE Online",
            bundleIdentifier: "com.ccpgames.eve",
            title: title,
            frame: CGRect(x: 0, y: 0, width: 1280, height: 720),
            instanceOrdinal: ordinal,
            preview: nil
        )
    }

    private func assignments(
        _ pairs: (CGWindowID, Int)...,
        windows: [CapturedWindow]
    ) -> [String: Int] {
        var result: [String: Int] = [:]
        let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        for (id, slot) in pairs {
            result[byID[id]!.overlayPositionKey] = slot
        }
        return result
    }

    func testPinnedWindowKeepsItsSlot() {
        let windows = [window(id: 1, title: "Alice"), window(id: 2, title: "Bob")]
        let pins = assignments((2, 3), windows: windows)

        let slots = HotKeySlotResolver.resolve(windows: windows, assignments: pins)
        XCTAssertEqual(slots[2], 2)
        // Unpinned window fills the first free slot, not the pinned one.
        XCTAssertEqual(slots[0], 1)
    }

    func testUnassignedWindowsFillSlotsInListOrder() {
        let windows = (1...3).map { window(id: CGWindowID($0), title: "T\($0)") }
        let slots = HotKeySlotResolver.resolve(windows: windows, assignments: [:])
        XCTAssertEqual(slots, [1, 2, 3, nil, nil, nil, nil, nil, nil])
    }

    func testNamelessWindowFillsFromLastSlot() {
        // A starting client has an empty title and sorts first; it must take
        // ⌘9, leaving the titled clients' auto-filled slots undisturbed.
        let nameless = window(id: 1, title: "")
        let alice = window(id: 2, title: "Alice")
        let bob = window(id: 3, title: "Bob")
        let slots = HotKeySlotResolver.resolve(windows: [nameless, alice, bob], assignments: [:])
        XCTAssertEqual(slots, [2, 3, nil, nil, nil, nil, nil, nil, 1])
    }

    func testMultipleNamelessWindowsStackBackward() {
        let first = window(id: 1, title: "")
        let second = window(id: 2, title: "")
        let alice = window(id: 3, title: "Alice")
        let slots = HotKeySlotResolver.resolve(windows: [first, second, alice], assignments: [:])
        XCTAssertEqual(slots, [3, nil, nil, nil, nil, nil, nil, 2, 1])
    }

    func testNamelessWindowRespectsPinnedTail() {
        // ⌘9 held by a pinned titled window: the nameless one takes ⌘8 next.
        let pinned = window(id: 1, title: "Zed")
        let nameless = window(id: 2, title: "")
        let pins = assignments((1, 9), windows: [pinned])
        let slots = HotKeySlotResolver.resolve(windows: [nameless, pinned], assignments: pins)
        XCTAssertEqual(slots[8], 1)
        XCTAssertEqual(slots[7], 2)
    }

    func testVanishedPinnedWindowFreesSlotForAutoFill() {
        let windows = [window(id: 1, title: "Alice"), window(id: 2, title: "Bob")]
        let pins = assignments((2, 2), windows: windows)

        // Bob's window vanishes; Alice is unpinned and must take slot 1,
        // not stay displaced by a slot owned by a window that no longer exists.
        let survivors = [windows[0]]
        let slots = HotKeySlotResolver.resolve(windows: survivors, assignments: pins)
        XCTAssertEqual(slots[0], 1)
        XCTAssertNil(slots[1])
    }

    func testDuplicatePinsResolveToListOrderFirstWins() {
        let windows = [window(id: 1, title: "Alice"), window(id: 2, title: "Bob")]
        // Defensive: the settings setter prevents this state, but a hand-edited
        // defaults file could still contain it. Earlier window wins the slot;
        // the loser falls back to auto-fill.
        let pins = assignments((1, 2), (2, 2), windows: windows)

        let slots = HotKeySlotResolver.resolve(windows: windows, assignments: pins)
        XCTAssertEqual(slots[1], 1)
        XCTAssertEqual(slots[0], 2)
    }

    func testWindowsBeyondNineGetNoSlot() {
        let windows = (1...11).map { window(id: CGWindowID($0), title: "T\($0)") }
        let slots = HotKeySlotResolver.resolve(windows: windows, assignments: [:])
        XCTAssertEqual(slots.compactMap { $0 }, Array(1...9))
        XCTAssertNil(HotKeySlotResolver.slot(of: 10, windows: windows, assignments: [:]))
        XCTAssertNil(HotKeySlotResolver.slot(of: 11, windows: windows, assignments: [:]))
    }

    func testSlotOfLookup() {
        let windows = [window(id: 1, title: "Alice"), window(id: 2, title: "Bob")]
        XCTAssertEqual(HotKeySlotResolver.slot(of: 1, windows: windows, assignments: [:]), 1)
        XCTAssertEqual(HotKeySlotResolver.slot(of: 2, windows: windows, assignments: [:]), 2)
        XCTAssertNil(HotKeySlotResolver.slot(of: 99, windows: windows, assignments: [:]))
    }

    func testOrderedWindowsFollowsSlotOrder() {
        let windows = [
            window(id: 1, title: "Alice"),
            window(id: 2, title: "Bob"),
            window(id: 3, title: "Carol")
        ]
        // Carol pinned to 1: order becomes Carol, Alice, Bob.
        let pins = assignments((3, 1), windows: windows)
        let ordered = HotKeySlotResolver.orderedWindows(windows, assignments: pins)
        XCTAssertEqual(ordered.map(\.id), [3, 1, 2])
    }

    @MainActor
    func testFactoryMenuActionPinsSlot() throws {
        let suiteName = "HotKeySlotResolverTests.menu.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        let capture = WindowCaptureService(settings: settings)
        let alice = window(id: 42, title: "Alice")

        let menu = WindowContextMenu.make(
            window: alice,
            capture: capture,
            settings: settings,
            includesOverlayToggle: false
        )
        // Structure: [activate, hotkey submenu root]
        let hotKeyRoot = try XCTUnwrap(menu.items[1].submenu)
        // [auto, separator, ⌘1, ⌘2, ⌘3, ...]
        XCTAssertEqual(hotKeyRoot.items.count, 2 + HotKeySlotResolver.slotCount)

        // Dispatch the item action directly on its target — the same call
        // AppKit's tracking session makes. (performActionForItem routes
        // through NSApp.sendAction and needs a run loop, so it is not a
        // faithful headless simulation.)
        let slotItem = try XCTUnwrap(hotKeyRoot.items[4])
        let target = try XCTUnwrap(slotItem.target as? ContextMenuAction)
        target.perform(slotItem)
        XCTAssertEqual(settings.hotKeyAssignments[alice.overlayPositionKey], 3)

        let autoItem = try XCTUnwrap(hotKeyRoot.items[0])
        let autoTarget = try XCTUnwrap(autoItem.target as? ContextMenuAction)
        autoTarget.perform(autoItem)
        XCTAssertNil(settings.hotKeyAssignments[alice.overlayPositionKey])
    }

    @MainActor
    func testSetHotKeySlotEvictsPreviousHolderAndPersists() throws {
        let suiteName = "HotKeySlotResolverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        let alice = window(id: 1, title: "Alice").overlayPositionKey
        let bob = window(id: 2, title: "Bob").overlayPositionKey

        settings.setHotKeySlot(3, for: alice)
        XCTAssertEqual(settings.hotKeyAssignments[alice], 3)

        settings.setHotKeySlot(3, for: bob)
        XCTAssertNil(settings.hotKeyAssignments[alice], "occupied slot must release the previous holder")
        XCTAssertEqual(settings.hotKeyAssignments[bob], 3)

        settings.setHotKeySlot(nil, for: bob)
        XCTAssertTrue(settings.hotKeyAssignments.isEmpty)

        // Out-of-range slots are treated as auto, never persisted.
        settings.setHotKeySlot(0, for: alice)
        settings.setHotKeySlot(10, for: alice)
        XCTAssertTrue(settings.hotKeyAssignments.isEmpty)

        // Assignments survive a fresh store over the same defaults.
        settings.setHotKeySlot(7, for: alice)
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.hotKeyAssignments[alice], 7)
    }
}
