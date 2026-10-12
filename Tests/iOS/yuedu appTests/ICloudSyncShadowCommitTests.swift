import Foundation
import Testing
@testable import yuedu_app

/// What a sync records as in step between this device and the cloud when its merged values
/// were not applied here.
///
/// Reported 2026-10-04 by a tester with two devices: books added on one were gone from it the
/// next day. The merge's shadow was stored before the merged shelf was applied. When the shelf
/// refused it — it had changed during the round trip — the next sync read the books that had
/// arrived, and were never applied, as deleted here, and sent their tombstones.
@Suite("iCloud sync shadow commit")
struct ICloudSyncShadowCommitTests {
    private struct Item: Codable, Equatable {
        var id: String
        var text: String
        var editedAt: Date
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var t1: Date { t0.addingTimeInterval(3_600) }
    private var t2: Date { t0.addingTimeInterval(7_200) }
    private var t3: Date { t0.addingTimeInterval(10_800) }

    private func hash(_ item: Item) -> String { item.text }

    private func live(_ item: Item, at date: Date) -> FirestoreSyncRecord<Item> {
        FirestoreSyncRecord(id: item.id, value: item, updatedAt: date, deleted: false)
    }

    private func entry(_ item: Item, at date: Date) -> SyncShadowEntry {
        SyncShadowEntry(updatedAt: date, hash: hash(item), deleted: false)
    }

    /// One sync: the merge, and the shadow it leaves given whether its values were applied.
    private func sync(
        local: [Item],
        remote: [FirestoreSyncRecord<Item>],
        shadow: [String: SyncShadowEntry],
        applied: Bool,
        now: Date
    ) -> (merge: (values: [Item], shadow: [String: SyncShadowEntry], shouldApplyLocally: Bool),
          committed: [String: SyncShadowEntry]) {
        let merge = ICloudSyncManager.resolveMerge(
            local: local, remote: remote, shadow: shadow,
            id: { $0.id }, hash: hash, fallbackUpdatedAt: { $0.editedAt }, now: now
        )
        let committed = ICloudSyncManager.shadowToCommit(
            previous: shadow, merge: merge, local: local, appliedLocally: applied,
            id: { $0.id }, hash: hash
        )
        return (merge, committed)
    }

    /// The report: a book added on the other device arrives while this shelf is changing,
    /// so it is not applied. The next sync adds it rather than sending its tombstone.
    @Test func aBookThatArrivedButWasNotAppliedIsAddedNextTime() {
        let kept = Item(id: "B", text: "kept", editedAt: t0)
        let added = Item(id: "X", text: "added elsewhere", editedAt: t1)
        let shadow = ["B": entry(kept, at: t0)]
        let remote = [live(kept, at: t0), live(added, at: t1)]

        let first = sync(local: [kept], remote: remote, shadow: shadow, applied: false, now: t2)
        #expect(first.merge.shouldApplyLocally)
        #expect(first.committed["X"] == nil, "X never reached this shelf")

        // The upload carried X, so the cloud has it; the shelf still has not.
        let second = sync(local: [kept], remote: remote, shadow: first.committed, applied: true, now: t3)
        #expect(second.merge.values.map(\.id) == ["B", "X"])
        #expect(second.merge.shouldApplyLocally)
        #expect(second.merge.shadow["X"]?.deleted == false)

        // What storing the whole shadow did: X read as deleted here.
        let before = sync(local: [kept], remote: remote, shadow: first.merge.shadow, applied: true, now: t3)
        #expect(before.merge.values.map(\.id) == ["B"])
        #expect(before.merge.shadow["X"]?.deleted == true)
    }

    /// An edit made on the other device — reading progress, a new source — that arrives
    /// while this shelf is changing wins again next time, instead of the stale copy here
    /// being stamped `now` and sent over it.
    @Test func anEditFromElsewhereThatWasNotAppliedIsNotRevertedNextTime() {
        let stale = Item(id: "B", text: "page 10", editedAt: t0)
        let edited = Item(id: "B", text: "page 80", editedAt: t1)
        let shadow = ["B": entry(stale, at: t0)]
        let remote = [live(edited, at: t1)]

        let first = sync(local: [stale], remote: remote, shadow: shadow, applied: false, now: t2)
        #expect(first.merge.values.map(\.text) == ["page 80"])
        #expect(first.committed["B"] == shadow["B"])

        let second = sync(local: [stale], remote: remote, shadow: first.committed, applied: true, now: t3)
        #expect(second.merge.values.map(\.text) == ["page 80"])
        #expect(second.merge.shouldApplyLocally)

        // What storing the whole shadow did: the stale copy won and went up.
        let before = sync(local: [stale], remote: remote, shadow: first.merge.shadow, applied: true, now: t3)
        #expect(before.merge.values.map(\.text) == ["page 10"])
    }

    /// What this device sent with the upload is in step all the same: a book added here,
    /// uploaded, and deleted before the sync finished still sends its tombstone next time
    /// rather than coming back from the cloud.
    @Test func whatThisDeviceSentIsInStepEvenWhenNothingWasApplied() {
        let kept = Item(id: "B", text: "kept", editedAt: t0)
        let addedHere = Item(id: "Y", text: "added here", editedAt: t1)
        let addedElsewhere = Item(id: "Z", text: "added elsewhere", editedAt: t1)
        let shadow = ["B": entry(kept, at: t0)]

        let first = sync(
            local: [kept, addedHere],
            remote: [live(kept, at: t0), live(addedElsewhere, at: t1)],
            shadow: shadow, applied: false, now: t2
        )
        #expect(first.committed["Y"]?.deleted == false)
        #expect(first.committed["Z"] == nil)

        // Y was deleted here while the sync ran; the cloud has what the upload carried.
        let second = sync(
            local: [kept],
            remote: [live(kept, at: t0), live(addedHere, at: t1), live(addedElsewhere, at: t1)],
            shadow: first.committed, applied: true, now: t3
        )
        #expect(second.merge.values.map(\.id) == ["B", "Z"])
        #expect(second.merge.shadow["Y"]?.deleted == true)
    }

    @Test func anAppliedMergeCommitsAllOfIt() {
        let kept = Item(id: "B", text: "kept", editedAt: t0)
        let added = Item(id: "X", text: "added elsewhere", editedAt: t1)
        let result = sync(
            local: [kept], remote: [live(kept, at: t0), live(added, at: t1)],
            shadow: ["B": entry(kept, at: t0)], applied: true, now: t2
        )
        #expect(result.committed == result.merge.shadow)
    }
}
