import Foundation
import Testing
@testable import yuedu_app

/// 立即閱讀 on a book's detail page reads a book that is not on the shelf. The copy it read
/// was a shelf book until the reader closed, so it synced while it was open, and a device on
/// 2.0.6 — which never takes a deletion — kept it as a second copy of the book (reported
/// 2026-10-04). It is a record off the shelf now.
@Suite("Trial reading record", .serialized)
@MainActor
struct TrialReadingRecordTests {
    private let sourceID = UUID()
    private let bookURL = "https://example.com/book/42"

    @Test("a trial copy is read, but neither shelved nor synced")
    func aTrialCopyIsReadButNeitherShelvedNorSynced() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookStore(metadataFileURL: directory.appendingPathComponent("books_meta.json"))

        let trial = addTrial(to: store)

        // What the shelf shows and the sync uploads.
        #expect(store.books.isEmpty)
        #expect(store.readingBook(id: trial.id)?.onlineChapters?.count == 3)
        #expect(store.onlineBook(sourceId: sourceID, bookInfoURL: bookURL) == nil, "not 已在書架")
        #expect(store.onlineBook(sourceId: sourceID, bookInfoURL: bookURL, onShelf: false)?.id == trial.id)
    }

    @Test("downloading a trial copy puts it on the shelf")
    func downloadingATrialCopyPutsItOnTheShelf() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookStore(metadataFileURL: directory.appendingPathComponent("books_meta.json"))
        let trial = addTrial(to: store)

        let downloading = store.ensureOnlineBookForDownload(try #require(store.readingBook(id: trial.id)))

        #expect(downloading.isInBookshelf)
        #expect(downloading.onlineChapters?.count == 3)
        #expect(store.books.map(\.id) == [trial.id])
    }

    private func addTrial(to store: BookStore) -> ReadingBook {
        store.addOnlineBook(
            name: "試讀", author: "作者",
            sourceId: sourceID, bookInfoURL: bookURL,
            chapters: (0..<3).map { OnlineChapterRef(index: $0, title: "第\($0 + 1)章", url: "\(bookURL)/\($0)") },
            isInBookshelf: false
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrialReadingRecordTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
