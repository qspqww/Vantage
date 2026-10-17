import CoreGraphics
import Foundation

/// Resolves ⌘1-9 hotkey slots for the current window set.
///
/// Assignments persist per client identity — the same `overlayPositionKey`
/// used for floating-panel positions — so a pinned client keeps its slot
/// across window-ID churn (fullscreen toggles) and relaunches. Windows
/// without an assignment fill the remaining slots in list order, so ⌘N
/// keeps working unchanged before the user customizes anything. Only live
/// windows occupy slots: a vanished client frees its slot immediately.
/// Pure functions so behavior is testable without AppKit.
struct HotKeySlotResolver {
    static let slotCount = 9

    /// WindowID occupying each slot (index 0 = ⌘1); nil marks an empty slot.
    /// Two identities pinned to one slot cannot both win — the earlier
    /// window in list order takes the slot and the loser falls back to
    /// auto-fill (the settings setter prevents this, the resolver guards it).
    /// Auto-fill direction differs by title: titled windows fill from ⌘1
    /// forward in list order, while nameless windows (clients still loading,
    /// empty title sorts first) fill from ⌘9 backward so a starting client
    /// never displaces the numbered slots established by titled ones.
    static func resolve(windows: [CapturedWindow], assignments: [String: Int]) -> [CGWindowID?] {
        var slots = [CGWindowID?](repeating: nil, count: slotCount)
        var unassignedTitled: [CapturedWindow] = []
        var unassignedNameless: [CapturedWindow] = []

        for window in windows {
            if let pinned = assignments[window.overlayPositionKey],
               (1...slotCount).contains(pinned),
               slots[pinned - 1] == nil {
                slots[pinned - 1] = window.id
            } else if window.title.isEmpty {
                unassignedNameless.append(window)
            } else {
                unassignedTitled.append(window)
            }
        }

        var nextFree = slots.firstIndex(of: nil)
        for window in unassignedTitled {
            guard let index = nextFree else { break }
            slots[index] = window.id
            nextFree = slots[(index + 1)...].firstIndex(of: nil)
        }

        var lastFree = slots.lastIndex(of: nil)
        for window in unassignedNameless {
            guard let index = lastFree else { break }
            slots[index] = window.id
            lastFree = index > 0 ? slots[..<index].lastIndex(of: nil) : nil
        }
        return slots
    }

    /// 1-based resolved slot for a window; nil when it has none. Reports what
    /// the shortcut actually does, not what is pinned — an unpinned window
    /// shows the slot it currently auto-fills.
    static func slot(of windowID: CGWindowID, windows: [CapturedWindow], assignments: [String: Int]) -> Int? {
        resolve(windows: windows, assignments: assignments)
            .firstIndex { $0 == windowID }
            .map { $0 + 1 }
    }

    /// Windows in hotkey order (⌘1 first). Drives next/previous cycling so
    /// ⌘⇧] / ⌘⇧[ step through clients in the same order as the number keys.
    static func orderedWindows(_ windows: [CapturedWindow], assignments: [String: Int]) -> [CapturedWindow] {
        let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        return resolve(windows: windows, assignments: assignments)
            .compactMap { $0.flatMap { byID[$0] } }
    }
}
