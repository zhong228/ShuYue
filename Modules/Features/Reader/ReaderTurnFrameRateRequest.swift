import QuartzCore

/// Asks the display for ProMotion rates while a page turns.
///
/// Measured on device (iPhone 16 Pro Max, 2026-10-05): UIKit's page curl ran at
/// 60fps — and at 30 or 20fps through 8 of 38 tapped turns in a burst — and the
/// slide turn's push ran at 60fps despite carrying its own 80–120Hz
/// `preferredFrameRateRange`, while a finger-driven slide in the same trace ran at
/// 120. Core Animation infers a rate for animations that do not ask for one, and
/// UIKit's curl offers nothing to annotate. A display link is the documented way
/// to ask: Core Animation arbitrates every request on screen, so while this one is
/// held the display runs at up to 120Hz and the turn is drawn at that rate. The
/// link does no work per frame.
///
/// Delete once a device trace shows curl and push turns at 120Hz without it.
@MainActor
final class ReaderTurnFrameRateRequest: NSObject {
    private var link: CADisplayLink?
    private var holds = 0

    var isActive: Bool { link != nil }

    /// Every `begin()` is paired with one `end()`; the request stays up while any
    /// turn still holds it.
    func begin() {
        holds += 1
        guard link == nil else { return }
        // The proxy holds this object weakly, so a reader torn down mid-turn takes
        // the link with it on its next tick.
        let link = DisplayLinkProxy.displayLink(
            target: self,
            selector: #selector(tick(_:)),
            preferredFPS: ReaderSlideTurnAnimation.frameRateRange
        )
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func end() {
        guard holds > 0 else { return }
        holds -= 1
        guard holds == 0 else { return }
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {}
}
