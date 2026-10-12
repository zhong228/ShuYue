import SwiftUI
import UIKit

/// One customization file opened from another app: read it, ask when its reading setup
/// is at stake, apply it, then show 匯入完成.
///
/// The question is a real alert and the report a real sheet, presented with UIKit over
/// whatever is on screen: the file can arrive while any tab, sheet or reader is up, and
/// SwiftUI's root cannot present over another presentation. It used to open a
/// full-screen page that held the question as a list of buttons, titled as if only the
/// header/footer were at stake.
@MainActor
final class SharedCustomizationImportFlow: NSObject {
    private let document: SharedCustomizationDocument
    private weak var window: UIWindow?
    private let read: (SharedCustomizationDocument) async throws -> SharedCustomizationImportService.Plan
    private let finish: () -> Void
    private weak var overview: UIViewController?
    private var isFinished = false

    init(
        document: SharedCustomizationDocument,
        window: UIWindow,
        read: @escaping (SharedCustomizationDocument) async throws -> SharedCustomizationImportService.Plan,
        finish: @escaping () -> Void
    ) {
        self.document = document
        self.window = window
        self.read = read
        self.finish = finish
    }

    func start() {
        Task { @MainActor in
            let plan: SharedCustomizationImportService.Plan
            do {
                plan = try await read(document)
            } catch {
                AppLogger.error("⟐ shared customization unreadable", error: error, context: [
                    "kind": "\(document.kind)",
                ])
                showFailure(Self.message(for: error))
                return
            }
            if let prompt = plan.prompt {
                ask(prompt, about: plan)
            } else {
                // Nothing to decide — a look, a theme pack, or a file with no layout.
                apply(plan)
            }
        }
    }

    // MARK: - Steps

    private func ask(_ prompt: CustomizationImportPrompt, about plan: SharedCustomizationImportService.Plan) {
        let alert = UIAlertController(title: prompt.title, message: prompt.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: localized(CustomizationImportPrompt.confirmTitleKey),
            style: .destructive
        ) { [self] _ in
            // UIKit calls this once the alert is gone, so the sheet can go straight up.
            apply(plan)
        })
        alert.addAction(UIAlertAction(title: localized("取消"), style: .cancel) { [self] _ in
            complete()
        })
        present(alert)
    }

    private func apply(_ plan: SharedCustomizationImportService.Plan) {
        let progress = CustomizationImportProgress()
        let sheet = UIHostingController(rootView: CustomizationImportOverviewView(progress: progress) { [weak self] in
            self?.dismissOverview()
        })
        sheet.presentationController?.delegate = self
        overview = sheet
        present(sheet)
        Task { @MainActor in
            do {
                progress.phase = .finished(try await SharedCustomizationImportService.apply(plan))
            } catch {
                AppLogger.error("⟐ shared customization import failed", error: error, context: [
                    "kind": "\(document.kind)",
                ])
                progress.phase = .failed(Self.message(for: error))
            }
        }
    }

    private func showFailure(_ message: String) {
        let alert = UIAlertController(title: localized("匯入失敗"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("確定"), style: .cancel) { [self] _ in
            complete()
        })
        present(alert)
    }

    private func dismissOverview() {
        guard let overview else {
            complete()
            return
        }
        overview.dismiss(animated: true) { [self] in complete() }
    }

    private func complete() {
        guard !isFinished else { return }
        isFinished = true
        finish()
    }

    // MARK: - Presentation

    /// Over whatever is on top of the window, once UIKit has finished any transition in
    /// flight — the same rule the book path follows, never a timed retry.
    private func present(_ controller: UIViewController) {
        guard let window, var top = window.rootViewController else {
            AppLogger.error("⟐ shared customization: no window to present on")
            complete()
            return
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        if let transition = top.transitionCoordinator,
           transition.animate(alongsideTransition: nil, completion: { [weak self] _ in
               self?.present(controller)
           }) {
            return
        }
        top.present(controller, animated: true)
    }

    static func message(for error: Error) -> String {
        if let themeError = error as? AppearanceThemeImportError {
            return localized(themeError.messageKey)
        }
        if let localizedError = error as? any LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return localized("匯入主題失敗。")
    }
}

extension SharedCustomizationImportFlow: UIAdaptivePresentationControllerDelegate {
    /// Swiping 匯入完成 away ends the flow the same way 完成 does. (While the import is
    /// still writing, the sheet refuses the swipe — see `CustomizationImportOverviewView`.)
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        complete()
    }
}
