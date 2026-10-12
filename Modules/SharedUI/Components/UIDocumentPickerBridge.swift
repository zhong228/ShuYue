import SwiftUI
import UniformTypeIdentifiers

// MARK: - UIDocumentPicker Bridge for AddBookView

/// SwiftUI wrapper presenting a `UIDocumentPickerViewController` as a sheet.
///
/// Replaces `.fileImporter` in `AddBookView` because iOS 18's `fileImporter`
/// `completion` handler is occasionally dropped after the user taps Open,
/// especially when the allowed-content-types list is long. The UIKit
/// delegate-based API is the proven path for reliable file selection.
///
/// `allowsMultipleSelection` is always `true`; `asCopy` is always `true` so the
/// returned URLs are plain sandbox URLs, not security-scoped ones.
struct UIDocumentPickerBridge: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController,
                                  context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void,
             onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            controller.dismiss(animated: true)
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            controller.dismiss(animated: true)
            onCancel()
        }
    }
}
