import Foundation
import Testing
@testable import yuedu_app

/// 新增或刪除一條劃線，其他劃線必須原封不動。
///
/// `addTextAnnotation`／`removeTextAnnotation` 曾經把全書的劃線整批刪掉再重建，重建時沒有帶回
/// 原本的 id、建立時間與摘錄：同章其他劃線的摘錄被換成這次選取的文字、別章的摘錄被清空、
/// 所有建立時間都變成「現在」。「重點」列表顯示的正是摘錄與時間。
@Suite("BookStore text annotations", .serialized)
struct BookStoreTextAnnotationTests {
    private let seededDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("adding an annotation leaves every other annotation untouched")
    @MainActor
    func addingKeepsOtherAnnotations() throws {
        let sameChapter = annotation(chapter: 0, offset: 2, length: 5, excerpt: "第一章的甲", note: "筆記甲")
        let otherChapter = annotation(chapter: 1, offset: 10, length: 4, excerpt: "第二章的乙", color: .blue)
        let (store, bookId, directory) = try makeStore(bookmarks: [sameChapter, otherChapter])
        defer { try? FileManager.default.removeItem(at: directory) }

        let newPosition = CoreTextReadingPosition(spineIndex: 0, charOffset: 40)
        store.addTextAnnotation(
            bookId: bookId,
            chapterIndex: 0,
            chapterTitle: "第1章",
            position: newPosition,
            length: 3,
            excerpt: "新選取",
            style: .highlight,
            color: .yellow
        )

        let bookmarks = try bookmarks(in: store, bookId: bookId)
        #expect(bookmarks.count == 3)
        #expect(bookmarks.contains(sameChapter))
        #expect(bookmarks.contains(otherChapter))
        let added = try #require(bookmarks.first { $0.position == newPosition })
        #expect(added.excerpt == "新選取")
    }

    @Test("removing an annotation leaves the rest of the book untouched")
    @MainActor
    func removingKeepsRemainingAnnotations() throws {
        let kept = annotation(chapter: 0, offset: 2, length: 5, excerpt: "留下的甲", note: "筆記甲")
        let removed = annotation(chapter: 0, offset: 40, length: 3, excerpt: "要刪的丙")
        let otherChapter = annotation(chapter: 1, offset: 10, length: 4, excerpt: "第二章的乙", color: .blue)
        let (store, bookId, directory) = try makeStore(bookmarks: [kept, removed, otherChapter])
        defer { try? FileManager.default.removeItem(at: directory) }

        store.removeTextAnnotation(
            bookId: bookId,
            position: removed.position,
            length: removed.length,
            style: .highlight,
            color: .yellow
        )

        let bookmarks = try bookmarks(in: store, bookId: bookId)
        #expect(bookmarks.count == 2)
        #expect(bookmarks.contains(kept))
        #expect(bookmarks.contains(otherChapter))
        #expect(!bookmarks.contains { $0.id == removed.id })
    }

    @Test("recoloring the same range keeps the annotation's id, date, excerpt and note")
    @MainActor
    func recoloringKeepsIdentity() throws {
        let original = annotation(chapter: 0, offset: 2, length: 5, excerpt: "原本的摘錄", note: "筆記")
        let (store, bookId, directory) = try makeStore(bookmarks: [original])
        defer { try? FileManager.default.removeItem(at: directory) }

        // 呼叫端沒有選取文字時會改送頁面開頭的文字（`currentPageExcerpt`），不能拿它蓋掉原本的摘錄。
        store.addTextAnnotation(
            bookId: bookId,
            chapterIndex: 0,
            chapterTitle: "第1章",
            position: original.position,
            length: original.length,
            excerpt: "頁面開頭的文字",
            style: .highlight,
            color: .green
        )

        let bookmarks = try bookmarks(in: store, bookId: bookId)
        #expect(bookmarks.count == 1)
        let recolored = try #require(bookmarks.first)
        #expect(recolored.id == original.id)
        #expect(recolored.date == original.date)
        #expect(recolored.excerpt == original.excerpt)
        #expect(recolored.note == original.note)
        #expect(recolored.annotationColor == .green)
    }

    @Test("extending an annotation keeps its original creation date")
    @MainActor
    func extendingKeepsEarliestDate() throws {
        let original = annotation(chapter: 0, offset: 2, length: 5, excerpt: "原本的摘錄")
        let (store, bookId, directory) = try makeStore(bookmarks: [original])
        defer { try? FileManager.default.removeItem(at: directory) }

        store.addTextAnnotation(
            bookId: bookId,
            chapterIndex: 0,
            chapterTitle: "第1章",
            position: CoreTextReadingPosition(spineIndex: 0, charOffset: 5),
            length: 8,
            excerpt: "延伸的選取",
            style: .highlight,
            color: .yellow
        )

        let bookmarks = try bookmarks(in: store, bookId: bookId)
        #expect(bookmarks.count == 1)
        let extended = try #require(bookmarks.first)
        #expect(extended.position == CoreTextReadingPosition(spineIndex: 0, charOffset: 2))
        #expect(extended.length == 11)
        #expect(extended.date == original.date)
    }

    // MARK: - Helpers

    private func annotation(
        chapter: Int,
        offset: Int,
        length: Int,
        excerpt: String,
        note: String = "",
        color: AnnotationColor = .yellow
    ) -> Bookmark {
        Bookmark(
            chapterIndex: chapter,
            chapterTitle: "第\(chapter + 1)章",
            position: CoreTextReadingPosition(spineIndex: chapter, charOffset: offset),
            length: length,
            kind: .highlight,
            note: note,
            excerpt: excerpt,
            date: seededDate,
            annotationStyle: .highlight,
            annotationColor: color
        )
    }

    @MainActor
    private func makeStore(bookmarks: [Bookmark]) throws -> (BookStore, UUID, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookStoreTextAnnotationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = BookStore(metadataFileURL: directory.appendingPathComponent("books_meta.json"))

        var book = ReadingBook(title: "劃線測試", author: "Author", contentFilename: "")
        book.isOnline = true
        book.contentPipelineKind = .html
        book.onlineChapters = (0..<3).map {
            OnlineChapterRef(index: $0, title: "第\($0 + 1)章", url: "https://example.com/\($0)")
        }
        book.bookmarks = bookmarks
        store.replaceBooksFromSync([book])

        let seeded = try self.bookmarks(in: store, bookId: book.id)
        try #require(seeded.count == bookmarks.count)
        return (store, book.id, directory)
    }

    @MainActor
    private func bookmarks(in store: BookStore, bookId: UUID) throws -> [Bookmark] {
        try #require(store.books.first { $0.id == bookId }).bookmarks
    }
}
