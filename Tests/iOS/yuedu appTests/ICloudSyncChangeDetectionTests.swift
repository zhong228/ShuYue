import Foundation
import Testing
@testable import yuedu_app

/// 15.trace and 16.trace (2026-09-22/23): the one reading hitch left in each was
/// the launch sync applying the shelf — `objectWillChange` re-rendered the reader
/// and the bookshelf behind it mid-scroll. Nothing had changed: the sync hash came
/// from an encoding whose key order differs on every call (and sets encoded in
/// storage order), so every item looked edited and every merge was applied.
@Suite("iCloud sync change detection")
struct ICloudSyncChangeDetectionTests {
    private let synced = Date(timeIntervalSince1970: 1_700_000_000)

    /// A shelf record as the device holds it: decoded from its own file.
    private func localBook(runtimeVariables: [String: String]? = ["token": "t-1", "uid": "42", "cookie": "c=1", "page": "3"],
                           downloading: Bool = true) throws -> ReadingBook {
        var book = ReadingBook(title: "書源小說", author: "作者", source: "https://example.com/book/1", contentFilename: "")
        book.isOnline = true
        book.runtimeVariables = runtimeVariables
        book.lastOpenedDate = synced
        if downloading {
            var task = BookOfflineDownloadTask(requestedIndices: Set(0..<40), now: synced)
            task.completedIndices = Set(0..<25)
            task.pendingIndices = Set(25..<40)
            book.offlineDownloadTask = task
        }
        return try JSONDecoder().decode(ReadingBook.self, from: JSONEncoder().encode(book))
    }

    /// The copy the next sync downloads: the uploaded blob, decoded again.
    private func cloudCopy(of book: ReadingBook) throws -> ReadingBook {
        let data = try ICloudSyncManager.encodeCloudSyncRecords([
            CloudSyncRecord(id: book.id.uuidString, value: book, updatedAt: synced, deleted: false)
        ])
        let records = try JSONDecoder().decode([CloudSyncRecord<ReadingBook>].self, from: data)
        return try #require(records.first?.value)
    }

    private func hash(_ book: ReadingBook) -> String {
        ICloudSyncManager.stableHash(book.strippedForSync())
    }

    /// The shadow hash the last sync wrote, from the record as it was then.
    private func lastSyncHash(_ book: ReadingBook) throws -> String {
        hash(try JSONDecoder().decode(ReadingBook.self, from: JSONEncoder().encode(book)))
    }

    private func merge(local: ReadingBook, remote: ReadingBook, remoteUpdatedAt: Date? = nil,
                       shadowHash: String, now: Date = Date())
        -> (values: [ReadingBook], shadow: [String: SyncShadowEntry], shouldApplyLocally: Bool) {
        let key = local.id.uuidString
        return ICloudSyncManager.resolveMerge(
            local: [local],
            remote: [FirestoreSyncRecord(id: key, value: remote, updatedAt: remoteUpdatedAt ?? synced, deleted: false)],
            shadow: [key: SyncShadowEntry(updatedAt: synced, hash: shadowHash, deleted: false)],
            id: { $0.id.uuidString },
            hash: hash,
            fallbackUpdatedAt: { $0.lastOpenedDate ?? $0.addedDate },
            now: now
        )
    }

    @Test func aBookBackFromTheCloudHashesLikeTheBookItCameFrom() throws {
        let book = try localBook()
        for round in 0..<20 {
            let copy = try cloudCopy(of: book)
            #expect(hash(copy) == hash(book), "round \(round)")
        }
    }

    /// The decision that re-rendered the reader: an unchanged shelf merged with
    /// its own last upload must not be applied.
    @Test func anUnchangedShelfIsNotAppliedAfterItsOwnRoundTrip() throws {
        let book = try localBook()
        for round in 0..<20 {
            let copy = try cloudCopy(of: book)
            let result = merge(local: book, remote: copy, shadowHash: hash(book))
            #expect(!result.shouldApplyLocally, "round \(round)")
        }
    }

    @Test func equalDownloadTasksEncodeIdentically() throws {
        let task = try #require(try localBook().offlineDownloadTask)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let original = try encoder.encode(task)
        for round in 0..<20 {
            let copy = try JSONDecoder().decode(BookOfflineDownloadTask.self, from: JSONEncoder().encode(task))
            #expect(try encoder.encode(copy) == original, "round \(round)")
        }
    }

    /// Before the fix the unedited local book looked edited, was stamped `now`
    /// and won, so another device's newer progress never arrived.
    @Test func aNewerEditFromAnotherDeviceIsApplied() throws {
        let book = try localBook()
        var edited = try cloudCopy(of: book)
        edited.currentPosition = 0.62
        let later = synced.addingTimeInterval(3_600)
        edited.lastOpenedDate = later
        let result = merge(local: book, remote: edited, remoteUpdatedAt: later,
                           shadowHash: try lastSyncHash(book), now: later.addingTimeInterval(3_600))
        #expect(result.values.map(\.currentPosition) == [0.62], "the other device's progress wins")
        #expect(result.shouldApplyLocally)
        #expect(result.shadow[book.id.uuidString]?.hash == hash(edited))
    }

    /// A real local edit still wins over the copy it was made from, and the shelf
    /// that already shows it is not re-applied.
    @Test func aLocalEditStillWins() throws {
        let book = try localBook()
        var edited = book
        edited.title = "改過的書名"
        let now = synced.addingTimeInterval(60)
        let copy = try cloudCopy(of: book)
        let result = merge(local: edited, remote: copy, shadowHash: try lastSyncHash(book), now: now)
        #expect(result.values.map(\.title) == ["改過的書名"])
        #expect(!result.shouldApplyLocally)
        #expect(result.shadow[book.id.uuidString]?.updatedAt == now)
    }
}
