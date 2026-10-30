import Foundation

/// What the paywall says, grouped the way readers weigh it: three benefits, each carried by
/// a few concrete things Pro does. Keys only — the view localizes them.
///
/// A row names a `PremiumFeature` so the paywall can mark the one that was tapped; the AI
/// feature is one entitlement but four rows, because 問書, 翻譯, 查詞 and 整理書架 are four
/// reasons to pay, not one.
enum PremiumPillar: String, CaseIterable, Identifiable {
    case understanding
    case comfort
    case habits

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .understanding: return "AI 读懂一本书"
        case .comfort: return "读得更舒服"
        case .habits: return "照你的习惯读"
        }
    }

    var iconName: String {
        switch self {
        case .understanding: return "sparkles"
        case .comfort: return "paintpalette"
        case .habits: return "hand.tap"
        }
    }

    /// What a buyer should know before paying for this pillar, or nil.
    var noteKey: String? {
        switch self {
        // Said up front: finding out after paying that AI needs your own key is a refund.
        case .understanding: return "AI 功能用你自己的 AI 服务金钥，支援 DeepSeek、OpenAI、Claude、Gemini 等。"
        case .comfort, .habits: return nil
        }
    }

    var benefits: [PremiumBenefit] {
        switch self {
        case .understanding:
            return [
                PremiumBenefit(feature: .aiReading, iconName: "bubble.left.and.text.bubble.right",
                               titleKey: "问书助手", detailKey: "看不懂就问，答案附原文出处，只根据你读过的部分回答"),
                PremiumBenefit(feature: .aiReading, iconName: "translate",
                               titleKey: "整章翻译", detailKey: "整章排成双语对照，或只看译文"),
                PremiumBenefit(feature: .aiReading, iconName: "character.book.closed",
                               titleKey: "AI 查词", detailKey: "选一个词，看它在这一句里的意思"),
                PremiumBenefit(feature: .paragraphNote, iconName: "note.text",
                               titleKey: "段落笔记", detailKey: "在划线旁写下想法，笔记跟著原文走"),
                PremiumBenefit(feature: .aiReading, iconName: "books.vertical",
                               titleKey: "AI 整理书架", detailKey: "帮整架书分好组，你确认了才套用"),
            ]
        case .comfort:
            return [
                PremiumBenefit(feature: .readerThemePacks, iconName: "paintpalette",
                               titleKey: "外观主题", detailKey: "App 与阅读配色、页面背景，都能自己调"),
                PremiumBenefit(feature: .readerBackgroundImport, iconName: "photo.on.rectangle.angled",
                               titleKey: "自订阅读背景", detailKey: "用自己的图片当书页背景"),
                PremiumBenefit(feature: .customFonts, iconName: "f.cursive",
                               titleKey: "字体汇入", detailKey: "汇入喜欢的字体，阅读和介面都能用"),
                PremiumBenefit(feature: .dialogueHighlight, iconName: "text.bubble",
                               titleKey: "对话气泡与高亮", detailKey: "对白排成聊天气泡，重点按规则自动上色"),
            ]
        case .habits:
            return [
                PremiumBenefit(feature: .touchZoneEditor, iconName: "hand.tap",
                               titleKey: "翻页区块", detailKey: "画面分成 3×3，每一格点了做什么由你决定"),
                PremiumBenefit(feature: .layoutPresetImport, iconName: "slider.horizontal.3",
                               titleKey: "排版备份", detailKey: "整套排版汇出汇入，也能读 Legado 的设定档"),
                PremiumBenefit(feature: .bottomBarCustomization, iconName: "square.grid.2x2",
                               titleKey: "底部分页", detailKey: "自订底部 Tab 的页面、大小与图示"),
                PremiumBenefit(feature: .launchScreen, iconName: "app.dashed",
                               titleKey: "启动图", detailKey: "换上你自己的开屏画面"),
            ]
        }
    }

    /// The pillar a feature is sold under.
    static func pillar(for feature: PremiumFeature) -> PremiumPillar? {
        allCases.first { pillar in pillar.benefits.contains { $0.feature == feature } }
    }

    /// Every pillar, the tapped feature's first: the reason they opened the paywall leads.
    static func ordered(leading feature: PremiumFeature?) -> [PremiumPillar] {
        guard let feature, let lead = pillar(for: feature) else { return allCases }
        return [lead] + allCases.filter { $0 != lead }
    }
}

struct PremiumBenefit: Identifiable, Equatable {
    let feature: PremiumFeature
    let iconName: String
    let titleKey: String
    let detailKey: String

    var id: String { titleKey }
}

/// The paywall's opening line: about what the reader just tapped, or about Pro as a whole
/// when they came from the Pro row.
struct PremiumPitch: Equatable {
    let headlineKey: String
    let pitchKey: String

    static func pitch(for feature: PremiumFeature?) -> PremiumPitch {
        switch feature {
        case .aiReading?:
            return .init(headlineKey: "读不懂的地方，问 AI 就好",
                         pitchKey: "问书、整章翻译、查词都附原文出处，只根据你读过的部分回答。")
        case .paragraphNote?:
            return .init(headlineKey: "在划线旁写下你的想法",
                         pitchKey: "笔记跟著原文段落走，随时翻回来都看得到。")
        case .customFonts?:
            return .init(headlineKey: "用你喜欢的字体读书",
                         pitchKey: "汇入字体档，阅读正文和 App 介面都能换上。")
        case .touchZoneEditor?:
            return .init(headlineKey: "翻页照你的手感",
                         pitchKey: "把画面分成 3×3 区块，每一格点了做什么由你决定。")
        case .dialogueHighlight?:
            return .init(headlineKey: "对白和重点一眼就看到",
                         pitchKey: "对话排成聊天气泡，关键字依规则自动上色。")
        case .layoutPresetImport?:
            return .init(headlineKey: "整套排版一键带走",
                         pitchKey: "字级、行距、标题样式与高亮一起汇出汇入，也能读 Legado 的设定档。")
        case .readerBackgroundImport?:
            return .init(headlineKey: "把喜欢的图片变成书页",
                         pitchKey: "汇入图片当阅读背景。")
        case .bottomBarCustomization?:
            return .init(headlineKey: "底部分页照你的顺序",
                         pitchKey: "自订底部 Tab 的页面、大小与图示。")
        case .readerThemePacks?:
            return .init(headlineKey: "整个 App 换成你的颜色",
                         pitchKey: "自订 App 与阅读配色，还有每一页的背景。")
        case .launchScreen?:
            return .init(headlineKey: "打开 App，先看到你的画面",
                         pitchKey: "换上自己的开屏图片。")
        case .alternateAppIcons?, nil:
            return .init(headlineKey: "每一本书，都读得更懂、更舒服",
                         pitchKey: "AI 读书助手、外观与字体、你的阅读习惯，一次解锁。")
        }
    }
}

/// Price framing for the plan cards.
enum PaywallPricing {
    /// How many months of the monthly plan the lifetime price equals, to the nearest half
    /// month — "约 7.5 个月的月费" — or nil when either price is missing or not positive.
    static func lifetimeInMonths(lifetime: Decimal, monthly: Decimal) -> Decimal? {
        guard lifetime > 0, monthly > 0 else { return nil }
        let months = NSDecimalNumber(decimal: lifetime / monthly).doubleValue
        guard months.isFinite, months >= 1 else { return nil }
        return Decimal((months * 2).rounded() / 2)
    }
}
