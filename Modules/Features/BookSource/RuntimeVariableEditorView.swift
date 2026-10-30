import SwiftUI

/// Legado-style variable editor sheet, shared by 設置源變量 (free-text variable a
/// source's JS reads via `source.getVariable()`) and 設置書籍變量 (the book's
/// runtime-variable map). The optional `comment` surfaces the source author's
/// `variableComment` guidance so users know what to fill in.
struct RuntimeVariableEditorView: View {
    let title: String
    let comment: String
    let initialValue: String
    /// Returns an error message to keep the sheet open, or nil to accept.
    let onSave: (String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var errorText: String?
    @State private var didLoadInitialValue = false

    var body: some View {
        NavigationStack {
            Form {
                if !comment.isEmpty {
                    Section(localized("变量说明")) {
                        Text(comment)
                            .font(DSFont.footnote)
                            .foregroundStyle(DSColor.textSecondary)
                            .textSelection(.enabled)
                    }
                    .interfaceSectionSurface()
                }
                Section {
                    TextEditor(text: $text)
                        .font(DSFont.subheadline)
                        .frame(minHeight: 200)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .dsSectionFooter(color: DSColor.destructive)
                    }
                }
                .interfaceSectionSurface()
                Section {
                    Button(role: .destructive) {
                        text = ""
                    } label: {
                        Label(localized("清除"), systemImage: "trash")
                    }
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            // The sections already carry `interfaceSectionSurface`, but the `Form` itself
            // was still painting an opaque grouped background over any page background.
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("储存")) {
                        if let error = onSave(text) {
                            errorText = error
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                guard !didLoadInitialValue else { return }
                didLoadInitialValue = true
                text = initialValue
            }
        }
    }
}

#Preview("源变量") {
    RuntimeVariableEditorView(
        title: "设置源变量",
        comment: "填入代理地址，例如 https://example.com\n第二行可填音质 1-3",
        initialValue: "{\"proxy\":\"https://example.com\"}",
        onSave: { _ in nil }
    )
}

#Preview("书籍变量") {
    RuntimeVariableEditorView(
        title: "设置书籍变量",
        comment: "",
        initialValue: "{}",
        onSave: { _ in "JSON 格式错误" }
    )
}
