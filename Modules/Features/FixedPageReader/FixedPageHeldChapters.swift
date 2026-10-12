import Foundation

// MARK: - Chapters the reader holds
//
// The paged reader holds one chapter at a time; the webtoon strip holds a run of them,
// growing at both ends as it scrolls, and numbers its pages straight through the run.
// This is what tells the container which chapter a strip page belongs to, and which
// chapter to load next at either end.
//
// The container used to keep one `chapterIndex` for all of it. Appending the next chapter
// moved that index forward while the reader was still on the chapter before, so scrolling
// back to the top prepended the chapter already on screen a second time, and the title and
// the saved position jumped a chapter ahead of the page being read.

struct FixedPageHeldChapters: Equatable {
    struct Chapter: Equatable {
        let index: Int
        let pageCount: Int
    }

    /// Where a held page sits in the book.
    struct Position: Equatable {
        let chapter: Int
        /// Page within its own chapter.
        let page: Int
        let chapterPageCount: Int
    }

    private(set) var chapters: [Chapter] = []

    /// The reader now shows `index` alone.
    mutating func reset(to index: Int, pageCount: Int) {
        chapters = [Chapter(index: index, pageCount: pageCount)]
    }

    mutating func clear() {
        chapters = []
    }

    /// The chapter to load below the last one held.
    var nextToAppend: Int? {
        chapters.last.map { $0.index + 1 }
    }

    /// The chapter to load above the first one held.
    var previousToPrepend: Int? {
        chapters.first.map { $0.index - 1 }
    }

    mutating func append(_ index: Int, pageCount: Int) {
        chapters.append(Chapter(index: index, pageCount: pageCount))
    }

    mutating func prepend(_ index: Int, pageCount: Int) {
        chapters.insert(Chapter(index: index, pageCount: pageCount), at: 0)
    }

    /// The chapter and page of the reader's `heldPage`, counted through every held chapter.
    func position(ofHeldPage heldPage: Int) -> Position? {
        guard heldPage >= 0 else { return nil }
        var remaining = heldPage
        for chapter in chapters {
            if remaining < chapter.pageCount {
                return Position(chapter: chapter.index, page: remaining, chapterPageCount: chapter.pageCount)
            }
            remaining -= chapter.pageCount
        }
        return nil
    }

    /// The reader's index for `page` of chapter `index`, or nil when that chapter is not held.
    func heldPage(forPage page: Int, inChapter index: Int) -> Int? {
        guard let position = chapters.firstIndex(where: { $0.index == index }) else { return nil }
        return chapters[..<position].reduce(0) { $0 + $1.pageCount } + page
    }
}
