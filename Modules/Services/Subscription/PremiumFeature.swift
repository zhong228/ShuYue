import Foundation

/// A capability unlocked by an active `MoYue Pro` subscription.
///
/// Gating is intentionally coarse in v1: every feature maps to the single
/// `isProActive` entitlement. The enum still enumerates each capability so the
/// UI can render per-feature rows, and so a future tiered plan can map features
/// to different entitlements without touching call sites.
enum PremiumFeature: String, CaseIterable, Identifiable, Hashable {
    /// Every AI feature: 助手, 整章翻譯, 選字的問 AI／解釋／查詞／翻譯, AI 整理書架.
    case aiReading
    case paragraphNote
    case customFonts
    case touchZoneEditor
    case dialogueHighlight
    case layoutPresetImport
    case readerBackgroundImport
    case bottomBarCustomization
    case readerThemePacks
    case alternateAppIcons
    case launchScreen

    var id: String { rawValue }

    /// Features that are implemented and may be advertised in Pro surfaces.
    /// Alternate app icons remain an internal capability key that does not ship and must
    /// not appear as marketing. `readerThemePacks` does ship — it gates 外觀主題's custom
    /// palettes and page backgrounds — and was missing from the paywall until 2026-09-27.
    static func marketedFeatures(highlighting highlightedFeature: PremiumFeature? = nil) -> [PremiumFeature] {
        let unavailable: Set<PremiumFeature> = [.alternateAppIcons]
        let available = allCases.filter { !unavailable.contains($0) }
        guard let highlightedFeature, available.contains(highlightedFeature) else {
            return available
        }
        return [highlightedFeature] + available.filter { $0 != highlightedFeature }
    }

    /// SF Symbol used in the Pro settings feature list and paywall.
    var iconName: String {
        switch self {
        case .aiReading: return "sparkles"
        case .paragraphNote: return "note.text"
        case .customFonts: return "f.cursive"
        case .touchZoneEditor: return "hand.tap"
        case .dialogueHighlight: return "text.bubble"
        case .layoutPresetImport: return "slider.horizontal.3"
        case .readerBackgroundImport: return "photo.on.rectangle.angled"
        case .bottomBarCustomization: return "square.grid.2x2"
        case .readerThemePacks: return "paintpalette"
        case .alternateAppIcons: return "app.badge"
        case .launchScreen: return "app.dashed"
        }
    }

    /// Localization key for the short feature title. Same words as the paywall's benefit
    /// rows (`PremiumPillar`), so a feature is called one thing everywhere Pro is sold.
    var titleKey: String {
        switch self {
        case .aiReading: return "AI 阅读助手"
        case .paragraphNote: return "段落笔记"
        case .customFonts: return "字体汇入"
        case .touchZoneEditor: return "翻页区块"
        case .dialogueHighlight: return "对话气泡与高亮"
        case .layoutPresetImport: return "排版备份"
        case .readerBackgroundImport: return "自订阅读背景"
        case .bottomBarCustomization: return "底部分页"
        case .readerThemePacks: return "外观主题"
        case .alternateAppIcons: return "桌面图标切换"
        case .launchScreen: return "启动图"
        }
    }

    /// Localization key for the one-line feature description: what the reader gets.
    var subtitleKey: String {
        switch self {
        case .aiReading: return "问书、整章翻译、查词与整理书架"
        case .paragraphNote: return "在划线旁写下想法，笔记跟著原文走"
        case .customFonts: return "汇入喜欢的字体，阅读和介面都能用"
        case .touchZoneEditor: return "画面分成 3×3，每一格点了做什么由你决定"
        case .dialogueHighlight: return "对白排成聊天气泡，重点按规则自动上色"
        case .layoutPresetImport: return "整套排版汇出汇入，也能读 Legado 的设定档"
        case .readerBackgroundImport: return "用自己的图片当书页背景"
        case .bottomBarCustomization: return "自订底部 Tab 的页面、大小与图示"
        case .readerThemePacks: return "App 与阅读配色、页面背景，都能自己调"
        case .alternateAppIcons: return "切换预置的桌面图标"
        case .launchScreen: return "换上你自己的开屏画面"
        }
    }

    var localizedTitle: String { localized(titleKey) }
    var localizedSubtitle: String { localized(subtitleKey) }
}
