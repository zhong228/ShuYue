import Foundation

// MARK: - Fixed page reading mode (ported concept from Aidoku's ReadingMode)

enum FixedPageReadingMode: Int, CaseIterable, Codable {
    case rtl = 1       // paged, right-to-left (default for CJK/Japanese manga)
    case ltr = 2       // paged, left-to-right
    case vertical = 3  // paged, vertical swipe
    case webtoon = 4   // continuous vertical scroll (manhua/manhwa)

    var localizedName: String {
        switch self {
        case .rtl:      return localized("从右到左")
        case .ltr:      return localized("从左到右")
        case .vertical: return localized("直向翻页")
        case .webtoon:  return localized("条漫")
        }
    }

    var iconName: String {
        switch self {
        case .rtl:      return "arrow.left"
        case .ltr:      return "arrow.right"
        case .vertical: return "arrow.up.arrow.down"
        case .webtoon:  return "arrow.down"
        }
    }
}
