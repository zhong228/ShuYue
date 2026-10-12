import UIKit

/// Pure math for the paged reader's pull-down-to-bookmark gesture. The whole page
/// is pulled down on a rubber band, a hint appears in the gap it leaves above
/// itself, and the page's own ribbon (`ReaderBookmarkRibbon`) grows out of its top
/// edge — or, on a page that already has one, retracts into it. Releasing past the
/// commit point keeps what the ribbon is showing; releasing short puts it back.
/// Scroll mode never installs this gesture, because there a downward drag is the
/// scroll itself.
///
/// Stateless like `ReaderSwipeUpExitMotion`, its mirror image, so the thresholds
/// are unit-testable without a view.
enum ReaderPullDownBookmarkMotion {
    /// Downward finger travel (pt) that maps to 100% progress.
    static let fullProgressTranslation: CGFloat = 180
    /// Progress at or above which releasing the finger toggles the bookmark. The
    /// ribbon reaches its end state exactly here, so what it shows is what a
    /// release will do.
    static let commitProgress: CGFloat = 0.55
    /// Downward fling velocity (pt/s, positive = down) that commits before the
    /// distance threshold is reached.
    static let commitVelocityY: CGFloat = 1100
    /// A fling still needs this much progress so a stray flick can't bookmark.
    static let flingMinimumProgress: CGFloat = 0.18

    /// The page's furthest drop (pt). Approached, never reached — it is the
    /// rubber band's asymptote.
    static let maxPageOffset: CGFloat = 220
    /// Finger travel over which the page gives up ~63% of `maxPageOffset`. Equal
    /// to it, so the page starts out following the finger one to one.
    static let pageOffsetTravel: CGFloat = 220
    /// Gap between the hint's bottom and the page's (moving) top edge.
    static let hintGap: CGFloat = 8
    /// The page springing back into place when the finger lifts.
    static let settleDuration: TimeInterval = 0.42
    /// A touch of overshoot, so the page lands rather than stops.
    static let settleBounce: CGFloat = 0.12
    /// Reduce Motion: a short ease home instead of the spring.
    static let reducedMotionSettleDuration: TimeInterval = 0.2

    /// The pan may only begin on a clearly downward drag, so horizontal
    /// page-turn pans and upward drags (the exit gesture) keep their behavior.
    static func shouldBegin(velocity: CGPoint) -> Bool {
        velocity.y > 0 && abs(velocity.y) > abs(velocity.x) * 1.4
    }

    static func progress(forTranslationY translationY: CGFloat) -> CGFloat {
        guard translationY > 0 else { return 0 }
        return min(translationY / fullProgressTranslation, 1)
    }

    /// How far the page itself has come down. Follows the finger at first and
    /// stiffens the further it goes, the way a scroll view overscrolls.
    static func pageOffset(forTranslationY translationY: CGFloat) -> CGFloat {
        guard translationY > 0 else { return 0 }
        return maxPageOffset * (1 - exp(-translationY / pageOffsetTravel))
    }

    /// The page ribbon's reveal (0 = retracted, 1 = hung) for this much pull. A
    /// bare page grows its ribbon; a bookmarked page draws its ribbon back in.
    /// Either way the change completes at the commit point.
    static func ribbonReveal(progress: CGFloat, wasBookmarked: Bool) -> CGFloat {
        let travel = min(max(progress, 0) / commitProgress, 1)
        return wasBookmarked ? 1 - travel : travel
    }

    /// Fades in over the first 40% of the pull so the hint never pops.
    static func hintAlpha(forProgress progress: CGFloat) -> CGFloat {
        min(max(progress, 0) * 2.5, 1)
    }

    /// Where the hint sits relative to the page's top edge: just above it, so it is
    /// off screen at rest and comes down with the page into the gap it opens.
    static func hintCenterY(hintHeight: CGFloat) -> CGFloat {
        -(hintGap + hintHeight / 2)
    }

    static func shouldCommit(progress: CGFloat, velocityY: CGFloat) -> Bool {
        if progress >= commitProgress { return true }
        return velocityY >= commitVelocityY && progress >= flingMinimumProgress
    }

    /// Where the pull stands. `isBookmarked` is read once when the gesture begins,
    /// so the hint never flips mid-drag because a neighbouring page settled under it.
    enum Phase: Equatable {
        /// Not yet far enough to commit.
        case pulling
        /// Past the commit point — release now and it happens.
        case armed
    }

    static func phase(forProgress progress: CGFloat) -> Phase {
        progress >= commitProgress ? .armed : .pulling
    }

    /// Localization key for the hint, resolved by the caller through `localized(_:)`.
    static func hintKey(isBookmarked: Bool, phase: Phase) -> String {
        switch (isBookmarked, phase) {
        case (false, .pulling): return "下拉加入書籤"
        case (false, .armed): return "放開加入書籤"
        case (true, .pulling): return "下拉移除書籤"
        case (true, .armed): return "放開移除書籤"
        }
    }

}
