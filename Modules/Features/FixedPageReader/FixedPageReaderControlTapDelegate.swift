import UIKit

/// Reader tap zones must not consume taps on embedded controls (for example Live Text).
/// Check ancestors too, since UIKit reports the label/image inside a button as the hit view.
@MainActor
final class FixedPageReaderControlTapDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        Self.acceptsReaderTap(on: touch.view)
    }

    /// A reader tap waits for the double tap that zooms, so the first tap of a double tap
    /// never turns the page or brings up the controls on its own.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer is FixedPageDoubleTapZoomGestureRecognizer
    }

    static func acceptsReaderTap(on view: UIView?) -> Bool {
        var candidate = view
        while let current = candidate {
            if current is UIControl { return false }
            candidate = current.superview
        }
        return true
    }
}
