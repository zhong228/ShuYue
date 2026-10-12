import SwiftUI
import UniformTypeIdentifiers

// MARK: - 文档选择器（UIKit 桥接）

/// SwiftUI 可用的 `UIDocumentPickerViewController` 包装器。
///
/// 为什么不用 SwiftUI 的 `.fileImporter`：iOS 18 上 `fileImporter` 的
/// `allowedContentTypes` 对来自「文件」App / 电脑同步的 .json 文件会灰显
/// 不可选（即使列表里包含 `public.item` 根类型也一样）。实测证明换成
/// UIKit 的 `UIDocumentPickerViewController(forOpeningContentTypes: [.item])`
/// 后一切文件都可选中，因此书源与图片的本地文件导入都走这里。
///
/// `asCopy: true` 让系统把选中文件复制进应用沙盒再返回 URL，返回的是普通
/// 本地路径而非 security-scoped URL，读取不受权限约束；`[.item]` 是
/// `public.item` 根类型，任何文件（含动态 UTI）都可以被点选。
/// 当前用于书源本地文件导入（见 `BookSourceListView`）。
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            controller.dismiss(animated: true)
            guard let url = urls.first else { return }
            parent.onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            controller.dismiss(animated: true)
            parent.onCancel()
        }
    }
}