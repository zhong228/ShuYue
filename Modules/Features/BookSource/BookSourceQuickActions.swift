import SwiftUI

/// A sheet a per-source action opens.
enum BookSourceActionSheet: Identifiable {
    case edit(BookSource)
    case login(BookSource)
    case variable(BookSource)

    var id: String {
        switch self {
        case .edit(let source): "edit-\(source.id)"
        case .login(let source): "login-\(source.id)"
        case .variable(let source): "variable-\(source.id)"
        }
    }
}

extension View {
    /// Presents the editor / login / variable sheets and the delete confirmation
    /// a source's action sheet chain can open.
    func bookSourceActionSheets(
        sheet: Binding<BookSourceActionSheet?>,
        pendingDeletion: Binding<BookSource?>
    ) -> some View {
        self
            .sheet(item: sheet) { action in
                switch action {
                case .edit(let source):
                    AdaptiveSheetContainer(maxWidth: DSLayout.readableExpandedWidth) {
                        BookSourceEditView(source: source) { updated in
                            BookSourceStore.shared.update(updated)
                        }
                    }
                case .login(let source):
                    BookSourceLoginSheet(source: source) { sheet.wrappedValue = nil }
                case .variable(let source):
                    AdaptiveSheetContainer(maxWidth: DSLayout.readablePanelWidth) {
                        RuntimeVariableEditorView(
                            title: localized("设置源变量"),
                            comment: SourceVariableEditing.comment(source: source),
                            initialValue: SourceVariableEditing.currentValue(for: source)
                        ) { value in
                            SourceVariableEditing.save(value, for: source)
                            return nil
                        }
                    }
                }
            }
            .confirmationDialog(
                localized("删除书源"),
                isPresented: Binding(
                    get: { pendingDeletion.wrappedValue != nil },
                    set: { if !$0 { pendingDeletion.wrappedValue = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion.wrappedValue
            ) { source in
                Button(localized("删除"), role: .destructive) {
                    _ = BookSourceStore.shared.delete(id: source.id)
                }
                Button(localized("取消"), role: .cancel) {}
            } message: { source in
                Text(source.bookSourceName)
            }
    }
}

/// A source's login: its own login form when it defines `loginUi`, otherwise the
/// login page in a web view.
struct BookSourceLoginSheet: View {
    let source: BookSource
    let onDone: () -> Void

    var body: some View {
        if source.loginUi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let webLogin = SourceWebLogin(bookSource: source) {
            SourceLoginWebView(login: webLogin, onDismiss: onDone)
        } else {
            BookSourceFormLoginView(source: source, onDismiss: onDone)
        }
    }
}
