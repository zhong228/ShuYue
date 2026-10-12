import Foundation

enum ReaderProgressSyncPolicy {
    /// All continuous text sources own live position in ReaderSessionStore. Publishing the
    /// library's entire record array on every gesture invalidates offscreen tabs.
    /// Data persistence remains unchanged; only UI observation is session-local.
    static func usesSessionLocalScrollProgress(
        isScrollMode: Bool, axis: CoreTextScrollAxis, hasScrollEngine: Bool
    ) -> Bool {
        isScrollMode && axis == .vertical && hasScrollEngine
    }

    /// A preview or failed migration cannot publish canonical chapter numbers.
    static func canPublishIndexPosition(isTXT: Bool, indexReady: Bool) -> Bool {
        !isTXT || indexReady
    }
    static func shouldPersistOnPageChanged(
        isCoreTextReady: Bool,
        totalPages: Int,
        isRestoringPosition: Bool
    ) -> Bool {
        isCoreTextReady && totalPages > 0 && !isRestoringPosition
    }
}
