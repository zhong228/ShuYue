import Foundation

/// Visibility rules for reader customization surfaces that should not be
/// discoverable until the single MoYue Pro entitlement is active.
struct ReaderPremiumVisibilityPolicy {
    let isProActive: Bool

    var showsReaderDecoration: Bool { isProActive }
    var showsBottomTabCustomization: Bool { isProActive }
    var showsBackgroundImageImport: Bool { isProActive }
    var showsLayoutPresetImport: Bool { isProActive }
    var showsTouchZoneEditor: Bool { isProActive }

    /// 新增／編輯段落筆記。**只鎖入口**：已經寫過的筆記，圓圈照常畫、內容照常讀得到，
    /// 過期只是不能再改——和專案其他 Pro 功能一樣，不動使用者已經產生的資料。
    var allowsParagraphNoteEditing: Bool { isProActive }

    /// Every AI feature (`PremiumFeature.aiReading`). Without Pro the only AI entries left
    /// are the reader's top menu and the bookshelf menu, marked Pro and opening the paywall.
    /// Chapter translations already made stay stored but are not laid out; the book's
    /// setting is kept for when Pro returns — a lapsed reader must not be stuck with a
    /// translated page behind a paywalled sheet.
    var allowsAI: Bool { isProActive }

    /// 匯入字體 (`PremiumFeature.customFonts`). Only the entry is locked — shown with a lock,
    /// opening the paywall: fonts imported earlier stay selectable and keep rendering.
    var allowsFontImport: Bool { isProActive }

    /// 問 AI／解釋／查詞／翻譯 in the text-selection menu. Hidden rather than locked: a
    /// paywall on every highlight would nag at the one gesture readers repeat most.
    var showsAISelectionActions: Bool { isProActive }

    func showsCommentBubbleSettings(hasParagraphReviews: Bool) -> Bool {
        isProActive && hasParagraphReviews
    }
}
