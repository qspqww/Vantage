import CoreGraphics
import Foundation

/// Session-pinned instance ordinals per (pid, title) group.
///
/// Replaces recomputing ordinals from the live window set every refresh cycle:
/// a pure function of the current set reshuffles ordinals whenever a member
/// drops out for one cycle (transient sub-320x180 size during fullscreen
/// toggles, empty title during loading screens). That reshuffle changed
/// overlay position keys, so a *surviving* window's panel jumped to the
/// vanished window's remembered spot — and jumped back a cycle later.
///
/// Instead, ordinals are assigned once per windowID and kept for the session.
/// A vanished member's ordinal is held as a tombstone for `graceInterval`;
/// a new windowID appearing in the same group within the grace window
/// reclaims the tombstone (fullscreen toggles recreate the window with a new
/// ID but the same identity), so its position key — and therefore its saved
/// overlay origin — survives the recreation. Pure value type, testable with
/// injected timestamps.
struct WindowOrdinalAllocator {
    struct GroupKey: Hashable {
        let pid: pid_t
        let title: String
    }

    let graceInterval: TimeInterval

    private var liveOrdinals: [GroupKey: [CGWindowID: Int]] = [:]
    private var tombstones: [GroupKey: [Int: Date]] = [:]

    init(graceInterval: TimeInterval = 4.0) {
        self.graceInterval = graceInterval
    }

    /// Returns the ordinal for every entry. Deterministic: new IDs are
    /// processed in ascending order, reclaiming the lowest tombstoned ordinal
    /// before taking the smallest unused one.
    mutating func assign(
        entries: [(pid: pid_t, title: String, id: CGWindowID)],
        now: Date
    ) -> [CGWindowID: Int] {
        var groups: [GroupKey: [CGWindowID]] = [:]
        for entry in entries {
            groups[GroupKey(pid: entry.pid, title: entry.title), default: []].append(entry.id)
        }

        // Groups that vanished entirely: retire their ordinals into tombstones.
        for key in Array(liveOrdinals.keys) where groups[key] == nil {
            let expiry = now.addingTimeInterval(graceInterval)
            var tomb = liveTombstones(for: key, now: now)
            for (_, ordinal) in liveOrdinals[key] ?? [:] {
                tomb[ordinal] = expiry
            }
            tombstones[key] = tomb.isEmpty ? nil : tomb
            liveOrdinals[key] = nil
        }

        var result: [CGWindowID: Int] = [:]
        for (key, ids) in groups {
            var live = liveOrdinals[key] ?? [:]
            var tomb = liveTombstones(for: key, now: now)

            for (id, ordinal) in live where !ids.contains(id) {
                tomb[ordinal] = now.addingTimeInterval(graceInterval)
                live[id] = nil
            }

            for id in ids.sorted() where live[id] == nil {
                if let reclaimed = tomb.keys.min() {
                    live[id] = reclaimed
                    tomb[reclaimed] = nil
                } else {
                    var ordinal = 0
                    let used = Set(live.values)
                    while used.contains(ordinal) { ordinal += 1 }
                    live[id] = ordinal
                }
            }

            liveOrdinals[key] = live.isEmpty ? nil : live
            tombstones[key] = tomb.isEmpty ? nil : tomb
            for (id, ordinal) in live {
                result[id] = ordinal
            }
        }
        return result
    }

    private func liveTombstones(for key: GroupKey, now: Date) -> [Int: Date] {
        (tombstones[key] ?? [:]).filter { $0.value > now }
    }
}
