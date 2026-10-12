import Foundation

/// 書籤清單的一章：章節標題一條，底下是這章的書籤，依書中順序排列。
///
/// 一頁一個書籤之後，一章可以有很多條，平舖成一列會讓同一個章名重複十幾次。
/// 分組讓章名只出現一次，並且成為「跳回本章開頭」的入口——章內每一條書籤
/// 各自跳回自己那一頁。
struct ReaderBookmarkChapterGroup: Identifiable, Equatable {
    let chapterIndex: Int
    let items: [Bookmark]

    var id: Int { chapterIndex }

    /// 依章節分組。章與章之間、章內各條之間都照書中位置排序，和閱讀順序一致。
    static func group(_ bookmarks: [Bookmark]) -> [ReaderBookmarkChapterGroup] {
        Dictionary(grouping: bookmarks.sortedByStablePosition(), by: \.chapterIndex)
            .map { ReaderBookmarkChapterGroup(chapterIndex: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                guard let left = lhs.items.first, let right = rhs.items.first else {
                    return lhs.chapterIndex < rhs.chapterIndex
                }
                return Bookmark.stablePositionSort(left, right)
            }
    }
}
