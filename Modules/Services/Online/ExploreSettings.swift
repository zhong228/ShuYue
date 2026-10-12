import Foundation

/// 探索設定 — what the 探索 page and its sources' pages show. Plain `UserDefaults` keys:
/// the views read them with `@AppStorage`, and discover loading reads them here, off the
/// main actor where it has to.
enum ExploreSettings {
    // MARK: 書源頁

    static let sourcePageLayoutKey = "explore.sourcePageLayout"

    // MARK: 探索首頁

    /// 发现页选中书源的 bookSourceUrl，关闭 App 再打开仍保持选中。
    static let selectedSourceURLKey = "explore.selectedSourceURL"

    // MARK: 榜單

    static let rankedKeywordsKey = "explore.rankedKeywords"
    static let chartBookCountKey = "explore.chartBookCount"
    static let shelfBookCountKey = "explore.shelfBookCount"
    static let preloadCountKey = "explore.preloadCount"

    /// Words that put a category in a numbered chart rather than a shelf of covers: the
    /// set 探索 matched before the list could be edited. A title matches a keyword
    /// whatever its letter case, so `top` also covers `TOP` and `Top`.
    static let defaultRankedKeywords = [
        "榜", "排行", "畅销", "暢銷", "热销", "熱銷", "热门", "熱門", "完本", "完结", "完結", "top",
    ]

    /// Books in each chart column: four, as before the setting.
    static let chartBookCountOptions = [3, 4, 5, 6, 8, 10]
    static let defaultChartBookCount = 4
    /// Books on each shelf; 0 shows the category's whole first page, as shelves always did.
    static let shelfBookCountOptions = [6, 8, 10, 12, 20, 0]
    static let defaultShelfBookCount = 0
    /// Categories queued after the one coming into view; 0, as before, queues none.
    static let preloadCountOptions = [0, 1, 2, 3, 5]
    static let defaultPreloadCount = 2
    /// 封面並發數 (`BookCoverLoader.downloadLimitKey`); 0, as before, sets no limit.
    static let coverDownloadLimitOptions = [2, 4, 6, 8, 0]

    static var rankedKeywords: [String] {
        guard let stored = UserDefaults.standard.string(forKey: rankedKeywordsKey) else {
            return defaultRankedKeywords
        }
        return decodeKeywords(stored)
    }

    /// One keyword per line: a keyword is a word, never a line break.
    static func encodeKeywords(_ keywords: [String]) -> String {
        keywords.joined(separator: "\n")
    }

    static func decodeKeywords(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static var preloadCount: Int {
        UserDefaults.standard.object(forKey: preloadCountKey) as? Int ?? defaultPreloadCount
    }
}

/// How a source's page lays out its categories.
enum ExploreSourcePageLayout: String, CaseIterable, Identifiable {
    /// Legado's: the categories along the top, the chosen one's books listed below.
    case list
    /// Each category as a shelf of covers or a numbered chart — Apple Books' store.
    case magazine

    static let `default` = ExploreSourcePageLayout.magazine

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .list: "列表"
        case .magazine: "雜誌"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .magazine: "square.grid.2x2"
        }
    }
}
