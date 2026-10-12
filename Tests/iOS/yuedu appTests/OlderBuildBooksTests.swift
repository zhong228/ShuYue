import Foundation
import Testing
@testable import yuedu_app

/// Since 2026-10-05 newer builds sync their own iCloud records, apart from devices still on
/// builds from before then (App Store 2.0.6, TestFlight up to 113), whose copies won every
/// conflict and whose tombstones took books away (reported 2026-10-04). Only the books those
/// devices add still come over, from the record they sync.
@Suite("Books from builds before the sync split", .serialized)
@MainActor
struct OlderBuildBooksTests {
    /// Not a book this device holds, and not one it deleted — before the split or since,
    /// which an older device keeps for good: only a book it has never known.
    @Test("only books this device never knew come over")
    func onlyBooksThisDeviceNeverKnewComeOver() {
        let items: [(id: String, deleted: Bool)] = [
            (id: "held", deleted: false),
            (id: "deleted before the split", deleted: false),
            (id: "deleted since", deleted: false),
            (id: "deleted over there", deleted: true),
            (id: "added over there", deleted: false),
        ]
        let known: Set<String> = ["held", "deleted before the split", "deleted since"]
        #expect(ICloudSyncManager.idsAddedByOlderBuilds(items, known: known) == ["added over there"])
    }

    /// By the id it carries, so it is one book when that device updates; and a book this
    /// device holds, on the shelf or only read, stays as it is.
    @Test("a book that comes over keeps its id and goes on the shelf")
    func aBookThatComesOverKeepsItsIDAndGoesOnTheShelf() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OlderBuildBooksTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookStore(metadataFileURL: directory.appendingPathComponent("books_meta.json"))
        let held = ReadingBook(title: "這台的書", author: "作者", source: "https://example.com/1", contentFilename: "")
        store.replaceBooksFromSync([held])

        var renamedThere = held
        renamedThere.title = "那台改過的書名"
        var added = ReadingBook(title: "那台加的書", author: "作者", source: "https://example.com/2", contentFilename: "")
        added.isInBookshelf = false

        #expect(store.adoptBooksAddedByOlderBuilds([renamedThere, added, added]) == 1)
        #expect(store.books.map(\.id) == [added.id, held.id])
        #expect(store.books.first { $0.id == held.id }?.title == "這台的書")
    }
}
