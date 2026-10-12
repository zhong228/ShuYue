import UIKit

/// The system share sheet for a file already written — for an export that asks for
/// its name first (匯出閱讀設定, 2026-09-29). Everything else shares through
/// `ShareLink`, which has to be the control that is tapped; here the tap belongs to the
/// name alert's 匯出 button, and `ShareLink` cannot be triggered from code.
///
/// Presented on the topmost view controller that is not on its way out. When that
/// controller is still mid-transition — the name alert being dismissed — the sheet
/// goes up from the transition's own completion, not after a delay.
@MainActor
enum SystemShareSheet {
    static func present(fileURL: URL) {
        guard let presenter = topmostViewController() else {
            AppLogger.error("⟐ share sheet: no window to present from", context: ["file": fileURL.lastPathComponent])
            return
        }
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            // iPad shows it as a popover, which needs an anchor; there is no row to
            // point at once the alert is gone, so it sits centred without an arrow.
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        if let coordinator = presenter.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in
                presenter.present(activity, animated: true)
            }
        } else {
            presenter.present(activity, animated: true)
        }
    }

    private static func topmostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
