import SwiftUI

struct AICustomPromptListView: View {
    @ObservedObject private var store = AICustomPromptStore.shared
    @State private var editing: AICustomPrompt?
    @State private var error: String?

    var body: some View {
        List {
            if let failure = error ?? store.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(DSColor.destructive)
            }
            if store.prompts.isEmpty {
                ContentUnavailableView {
                    UnavailableLabel(localized("还没有自订提示词"), systemImage: "text.badge.plus")
                } description: {
                    Text(localized("常用的问法存成提示词，就会出现在 AI 对话的快捷按钮里。")).foregroundStyle(DSColor.textSecondary)
                } actions: {
                    Button(localized("新增提示词")) { editing = .init(title: "", instruction: "") }
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.prompts) { prompt in
                    Button { editing = prompt } label: { row(prompt) }
                }
                .onDelete { indices in update { $0.remove(atOffsets: indices) } }
                .onMove { source, destination in update { $0.move(fromOffsets: source, toOffset: destination) } }
            }
        }
        .softScrollEdges()
        .navigationTitle(localized("自订提示词"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .toolbar {
            if !store.prompts.isEmpty {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .init(title: "", instruction: "") } label: { Image(systemName: "plus") }
                    .accessibilityLabel(localized("新增提示词"))
            }
        }
        .sheet(item: $editing) { prompt in
            AICustomPromptEditor(prompt: prompt) { value in
                var values = store.prompts
                if let index = values.firstIndex(where: { $0.id == value.id }) { values[index] = value }
                else { values.append(value) }
                try store.save(values)
            }
        }
    }

    /// Name, then where it shows up — or that it is off — and the start of the instruction.
    private func row(_ prompt: AICustomPrompt) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(prompt.title)
                .foregroundStyle(prompt.isEnabled ? DSColor.textPrimary : DSColor.textSecondary)
            Text(verbatim: "\(prompt.isEnabled ? prompt.context.title : localized("停用")) · \(prompt.instruction)")
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
        }
    }

    private func update(_ change: (inout [AICustomPrompt]) -> Void) {
        var values = store.prompts
        change(&values)
        do { try store.save(values) } catch { self.error = error.localizedDescription }
    }
}

private struct AICustomPromptEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var prompt: AICustomPrompt
    let save: (AICustomPrompt) throws -> Void
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(localized("名称"), text: $prompt.title)
                    Picker(localized("使用情境"), selection: $prompt.context) {
                        ForEach(AICustomPrompt.Context.allCases, id: \.self) { context in
                            Text(context.title).tag(context)
                        }
                    }
                    Toggle(localized("启用"), isOn: $prompt.isEnabled)
                }
                Section {
                    TextEditor(text: $prompt.instruction)
                        .frame(minHeight: DSLayout.minimumTapTarget * 4)
                        .accessibilityLabel(localized("提示词内容"))
                } header: { Text(localized("提示词内容")).foregroundStyle(DSColor.textSecondary) }
                footer: { Text(localized("选文与阅读内容会自动带入，仍受对话的已读范围限制。")).dsSectionFooter() }
            }
            .softScrollEdges()
            .alert(localized("无法储存"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(localized("确定"), role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
            .navigationTitle(localized("自订提示词"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(localized("取消"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        do { try save(prompt); dismiss() } catch { failure = error.localizedDescription }
                    } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel(localized("储存"))
                        .disabled(prompt.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview { NavigationStack { AICustomPromptListView() } }
