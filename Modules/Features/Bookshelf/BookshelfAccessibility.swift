import Foundation

/// Both shelf layouts expose the same single book focus and rotor actions.
enum BookshelfAccessibility {
    static func description(for book: ReadingBook) -> String {
        var parts = [book.title]
        if !book.author.isEmpty { parts.append(book.author) }
        if book.resolvedPipelineKind == .audio { parts.append(localized("有聲書")) }
        if let latest = book.latestChapterDisplayTitle {
            parts.append(localized("最新") + "，" + latest)
        }
        if book.hasNewChapterUpdate { parts.append(localized("有新章節")) }
        if book.shouldShowNewOnBookshelf {
            parts.append(localized("新增"))
        } else if book.currentPosition >= 0.99 {
            parts.append(localized("已讀完"))
        } else {
            parts.append(String(format: localized("已讀 %d%%"), Int(book.currentPosition * 100)))
        }
        if book.offlineDownloadState == .downloading { parts.append(localized("下載中")) }
        return parts.joined(separator: "，")
    }
}
