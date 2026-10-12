import Combine

/// Presentation mirrors for chapter-dependent controls. The reader session owns
/// the canonical (spine, character) position; these values never persist it.
@MainActor
final class ReaderChapterPresentationState: @MainActor ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private(set) var currentChapter = 0
    private(set) var visibleChapter = 0
    // Ordinary navigation may return to the value the root last rendered before
    // several silent scroll commits. Observe its revision, not that old value.
    private(set) var currentChangeRevision: UInt64 = 0
    private(set) var visibleChangeRevision: UInt64 = 0
    private var handledCurrentChapter = 0
    private var handledVisibleChapter = 0

    struct Change {
        let current: Bool
        let visible: Bool
        var any: Bool { current || visible }
    }

    func setCurrentChapter(_ value: Int) {
        guard currentChapter != value else { return }
        objectWillChange.send()
        currentChapter = value
        currentChangeRevision &+= 1
    }

    func setVisibleChapter(_ value: Int) {
        guard visibleChapter != value else { return }
        objectWillChange.send()
        visibleChapter = value
        visibleChangeRevision &+= 1
    }

    /// Reading only refreshes the session-observing bars/status overlay. Open
    /// navigation controls still receive a chapter change immediately.
    func commitScrollChapter(_ chapter: Int, controlsVisible: Bool) -> Change {
        let change = Change(current: currentChapter != chapter, visible: visibleChapter != chapter)
        if change.any && controlsVisible { objectWillChange.send() }
        currentChapter = chapter
        visibleChapter = chapter
        // The caller delivers these effects directly after updating the session.
        // A later unrelated root update must not replay its old onChange values.
        handledCurrentChapter = chapter
        handledVisibleChapter = chapter
        return change
    }

    func consumeCurrentChapterChange() -> Bool {
        guard handledCurrentChapter != currentChapter else { return false }
        handledCurrentChapter = currentChapter
        return true
    }

    func consumeVisibleChapterChange() -> Bool {
        guard handledVisibleChapter != visibleChapter else { return false }
        handledVisibleChapter = visibleChapter
        return true
    }
}
