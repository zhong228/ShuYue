import Foundation

extension AIReaderAnnotation {
    /// Underlines and highlights with their excerpt, and any mark carrying a note. A plain
    /// bookmark has neither and is left out.
    init?(_ bookmark: Bookmark, bookTitle: String?) {
        let excerpt = bookmark.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = bookmark.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (bookmark.kind != .bookmark && !excerpt.isEmpty) || !note.isEmpty else { return nil }
        self.init(id: bookmark.id, bookTitle: bookTitle, chapterIndex: bookmark.position.spineIndex,
                  chapterTitle: bookmark.chapterTitle, excerpt: excerpt, note: note, date: bookmark.date)
    }
}
