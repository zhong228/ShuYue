import SwiftUI

// MARK: - Bookstore Channel

/// 书城页顶部的频道流栏目。书城把原发现页拆成五个横向切换的频道：精选
/// （featured 横滑封面）、排行榜（ranked 榜单）、新书（标题含“新/最新”等词
/// 的分类）、分类（该书源的全部分类）、我的页面（用户自建的自定义页）。
enum BookstoreChannel: String, CaseIterable, Identifiable {
    /// 精选：source 的 featured 分类（封面横滑书架）。
    case featured
    /// 排行榜：source 的 ranked 分类（榜单竖排）。
    case ranked
    /// 新书：标题含“新/最新/更新/新上架”等词的分类。
    case newBooks
    /// 分类：source 的全部 fetchable 分类。
    case categories
    /// 我的页面：用户的 CustomExplorePage 列表。
    case myPages

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .featured: "精选"
        case .ranked: "排行榜"
        case .newBooks: "新书"
        case .categories: "分類"
        case .myPages: "我的頁面"
        }
    }

    var systemImage: String? {
        switch self {
        case .featured: "sparkles"
        case .ranked: "list.number"
        case .newBooks: "clock"
        case .categories: "square.grid.2x2"
        case .myPages: "rectangle.stack"
        }
    }

    /// 匹配“新书”的词：标题含任一词的分类当作新书频道内容。
    static let newBookKeywords = ["新书", "新書", "最新", "更新", "新上架", "新進"]

    func matches(_ section: DiscoverShowcaseSection) -> Bool {
        switch self {
        case .featured:
            return section.style == .featured
        case .ranked:
            return section.style == .ranked
        case .newBooks:
            return Self.newBookKeywords.contains { keyword in
                !keyword.isEmpty && section.title.range(of: keyword) != nil
            }
        case .categories:
            return true
        case .myPages:
            return false
        }
    }
}