import Combine
import Foundation
import Testing
@testable import yuedu_app

/// Guards the two paths a device trace caught dropping frames while the user
/// scrolled: a library publish re-evaluating the whole bookshelf behind the open
/// reader, and the reader's clock re-evaluating the whole reader.
///
/// `BookStore.records` is `@Published`, and `ContentView`, `HomeView` and
/// `BookReaderView` each hold an `@EnvironmentObject store`, so one publish costs
/// every shelf row a body. Position writes that move nothing must therefore not
/// publish at all.
@Suite("Shelf re-render budget", .serialized)
struct ShelfRerenderBudgetTests {

    @Test("re-saving the same reading position does not publish")
    @MainActor
    func repeatedPositionDoesNotPublish() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        harness.store.updatePosition(bookId: harness.bookID, position: 0.5)
        #expect(harness.publishCount == 1)
        #expect(harness.store.books.first?.currentPosition == 0.5)

        harness.store.updatePosition(bookId: harness.bookID, position: 0.5)
        harness.store.updatePosition(bookId: harness.bookID, position: 0.5, forceSave: true)
        #expect(harness.publishCount == 1)

        harness.store.updatePosition(bookId: harness.bookID, position: 0.75)
        #expect(harness.publishCount == 2)
        #expect(harness.store.books.first?.currentPosition == 0.75)
    }

    /// A forced save has to be able to flush a value that is already in memory but
    /// never reached disk, so skipping the *publish* must not skip the save.
    @Test("a forced save of an unchanged position still persists")
    @MainActor
    func forcedSaveOfUnchangedPositionStillPersists() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        harness.store.updatePosition(bookId: harness.bookID, position: 0.0001)
        harness.store.updatePosition(bookId: harness.bookID, position: 0.0001, forceSave: true)

        let reloaded = BookStore(metadataFileURL: harness.metadataURL)
        #expect(reloaded.books.first?.currentPosition == 0.0001)
    }

    /// Continuous scroll writes its position without notifying the library views,
    /// and its lifecycle save shows that position by writing it again with
    /// notification. That second write carries the same value, so skipping
    /// unchanged writes must not skip it — the shelf would keep the opening position.
    @Test("a notifying save publishes a position written silently before it")
    @MainActor
    func notifyingSaveShowsASilentlyWrittenPosition() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        harness.store.updatePosition(bookId: harness.bookID, position: 0.4, notifyLibraryViews: false)
        harness.store.updatePosition(bookId: harness.bookID, position: 0.6, notifyLibraryViews: false)
        #expect(harness.publishCount == 0)
        #expect(harness.store.books.first?.currentPosition == 0.6)

        harness.store.updatePosition(bookId: harness.bookID, position: 0.6, forceSave: true, notifyLibraryViews: true)
        #expect(harness.publishCount == 1, "the lifecycle save shows the silent progress")

        harness.store.updatePosition(bookId: harness.bookID, position: 0.6, forceSave: true, notifyLibraryViews: true)
        #expect(harness.publishCount == 1, "and then the value is published, so the next same write is a no-op")
    }

    @Test("re-saving the same manga position does not publish")
    @MainActor
    func repeatedMangaPositionDoesNotPublish() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        harness.store.updateMangaPosition(
            bookId: harness.bookID, chapter: 3, page: 7, totalChapters: 10
        )
        #expect(harness.publishCount == 1)

        harness.store.updateMangaPosition(
            bookId: harness.bookID, chapter: 3, page: 7, totalChapters: 10
        )
        #expect(harness.publishCount == 1)

        harness.store.updateMangaPosition(
            bookId: harness.bookID, chapter: 3, page: 8, totalChapters: 10
        )
        #expect(harness.publishCount == 2)
        #expect(harness.store.books.first?.mangaPage == 8)
    }

    @Test("re-saving the same audio position does not publish")
    @MainActor
    func repeatedAudioPositionDoesNotPublish() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        harness.store.updateAudioPosition(
            bookId: harness.bookID, chapter: 2, time: 90, totalChapters: 10
        )
        #expect(harness.publishCount == 1)

        harness.store.updateAudioPosition(
            bookId: harness.bookID, chapter: 2, time: 90, totalChapters: 10
        )
        #expect(harness.publishCount == 1)

        harness.store.updateAudioPosition(
            bookId: harness.bookID, chapter: 2, time: 120, totalChapters: 10
        )
        #expect(harness.publishCount == 2)
        #expect(harness.store.books.first?.audioTimeSeconds == 120)
    }

    /// `ClockBatteryModel` publishes `now` on a minute-aligned timer. Held as an
    /// observed object on `ReaderView` it invalidated the entire reader body — ~13 ms
    /// on E cores in a device trace, a dropped frame at 120 Hz when the minute rolled
    /// over mid-fling. `ReaderPageBarsLayer` owns it now; the reader reads the
    /// readings back from `ReaderPageBarsController` without subscribing.
    @Test("ReaderView does not observe the reader clock")
    func readerViewDoesNotObserveTheClock() throws {
        let readerView = try String(
            contentsOf: Self.repositoryRoot
                .appendingPathComponent("Modules/Features/Reader/ReaderView.swift"),
            encoding: .utf8
        )
        for wrapper in ["@StateObject", "@ObservedObject", "@EnvironmentObject"] {
            #expect(
                !readerView.contains("\(wrapper) var readerOverlayClock"),
                "ReaderView must not subscribe to the clock via \(wrapper)"
            )
        }
        #expect(readerView.contains("var readerOverlayClock: ReaderOverlayClockSnapshot"))

        let barsLayer = try String(
            contentsOf: Self.repositoryRoot
                .appendingPathComponent("Modules/Features/Reader/ReaderBarsView.swift"),
            encoding: .utf8
        )
        #expect(barsLayer.contains("@StateObject private var clock = ClockBatteryModel()"))
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// One online book on the shelf plus a live count of `objectWillChange` emissions.
    @MainActor
    private final class Harness {
        let directory: URL
        let metadataURL: URL
        let store: BookStore
        let bookID: UUID

        private var cancellable: AnyCancellable?
        private var publishes = 0

        var publishCount: Int { publishes }

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ShelfRerenderBudgetTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            metadataURL = directory.appendingPathComponent("books_meta.json")
            store = BookStore(metadataFileURL: metadataURL)

            var book = ReadingBook(title: "Online Book", author: "Author", contentFilename: "")
            book.isOnline = true
            book.contentPipelineKind = .html
            book.onlineChapters = (0..<10).map {
                OnlineChapterRef(index: $0, title: "Chapter \($0)", url: "https://example.com/\($0)")
            }
            bookID = book.id
            // Seeded before subscribing, so only the writes under test are counted.
            store.replaceBooksFromSync([book])
            cancellable = store.objectWillChange.sink { [weak self] _ in
                // `records` is only ever written from the main actor, and every write
                // under test is made by the test itself.
                MainActor.assumeIsolated { self?.publishes += 1 }
            }
        }

        func tearDown() {
            cancellable = nil
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
