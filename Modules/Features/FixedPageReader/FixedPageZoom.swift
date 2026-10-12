import UIKit
import VisionKit

// MARK: - Zoom pieces shared by both layouts
//
// A fixed page zooms with a pinch or a double tap, in the paged and the webtoon
// layout alike. The reader's single tap (turn the page, bring up the controls) waits
// for that double tap to fail, or the first tap of every double tap would act on its
// own; and a double tap switched off in settings must not keep it waiting.

enum FixedPageZoom {
    /// Largest zoom, as a multiple of the fitted size.
    static let maximumScale: CGFloat = 5
    /// Where a double tap on a fitted page zooms to.
    static let doubleTapScale: CGFloat = 2

    /// Zoomed in, past what a spring-back or rounding leaves behind at the fitted size.
    static func isZoomedIn(_ scale: CGFloat) -> Bool {
        scale > 1.01
    }

    /// Live Text's button sits on every page. It shows with the reader's controls and
    /// goes with them, as in Aidoku; zoomed in it goes too, so it never covers what is
    /// being read.
    static func showsLiveTextButton(controlsShown: Bool, zoomScale: CGFloat) -> Bool {
        controlsShown && !isZoomedIn(zoomScale)
    }
}

/// The double tap that zooms. A type of its own so the reader's single tap can wait
/// for exactly this recognizer (`FixedPageReaderControlTapDelegate`) and nothing else.
final class FixedPageDoubleTapZoomGestureRecognizer: UITapGestureRecognizer {
    private let gate = FixedPageDoubleTapZoomGate()

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        numberOfTapsRequired = 2
        delegate = gate
    }
}

/// Keeps the double tap out of the touches it must not see: taps on a control such as
/// the retry button, and every touch while double-tap zoom is off in settings. A
/// recognizer that never receives a touch is never waited for, so switching the
/// setting off makes the single tap act at once — in a reader that is already open too.
@MainActor
final class FixedPageDoubleTapZoomGate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        Self.acceptsDoubleTap(isEnabled: GlobalSettings.shared.fixedPageDoubleTapToZoom, on: touch.view)
    }

    static func acceptsDoubleTap(isEnabled: Bool, on view: UIView?) -> Bool {
        isEnabled && FixedPageReaderControlTapDelegate.acceptsReaderTap(on: view)
    }
}

extension ImageAnalysisInteraction {
    /// Shows or hides the Live Text button — except while its text is picked out: the
    /// button is then the reader's way back out of that, so it stays.
    func setLiveTextButtonHidden(_ hidden: Bool) {
        guard !selectableItemsHighlighted else { return }
        setSupplementaryInterfaceHidden(hidden, animated: true)
    }
}
