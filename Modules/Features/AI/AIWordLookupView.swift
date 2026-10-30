import SwiftUI

/// AI 查詞: a half-height card with the selected word and the model's explanation of it in
/// its sentence. Follow-up questions go to the assistant through 繼續問 AI.
struct AIWordLookupView: View {
    @StateObject private var model: AIWordLookupModel
    private let onAskAI: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var copyCount = 0

    init(term: String, context: String, bookTitle: String?, bookID: UUID, onAskAI: (() -> Void)? = nil,
         provider: (any LLMProviding)? = nil) {
        _model = StateObject(wrappedValue: AIWordLookupModel(term: term, context: context, bookTitle: bookTitle,
                                                             bookID: bookID, provider: provider))
        self.onAskAI = onAskAI
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    Text(model.term)
                        .font(DSFont.title2.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                        .textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.md)
            }
            .softScrollEdges()
            .background(DSColor.background)
            .navigationTitle(localized("AI 查词"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(localized("关闭"))
                }
                if case .finished = model.state {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            UIPasteboard.general.string = model.answer
                            copyCount += 1
                            AccessibilityNotification.Announcement(localized("已复制")).post()
                        } label: {
                            Label(localized("复制"), systemImage: "doc.on.doc")
                        }
                        .sensoryFeedback(.success, trigger: copyCount)
                        Spacer()
                        if let onAskAI {
                            Button(action: onAskAI) {
                                ToolbarTitleAndIconLabel(
                                    title: localized("继续问 AI"),
                                    systemImage: "bubble.left.and.text.bubble.right",
                                    width: DSLayout.aiWordLookupAskLabelWidth
                                )
                            }
                            .accessibilityLabel(localized("继续问 AI"))
                            .accessibilityIdentifier("ai_word_lookup_ask_ai")
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { if model.state == .idle { model.start() } }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .streaming(""):
            HStack(spacing: DSSpacing.sm) {
                ProgressView()
                Text(localized("查询中…"))
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .accessibilityElement(children: .combine)
        case let .streaming(text), let .finished(text):
            AIAnswerMarkdownView(text: text)
        case let .failed(message):
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(DSColor.destructive)
                Button(localized("重试")) { model.start() }
                    .buttonStyle(.bordered)
            }
        case let .unavailable(message):
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text(message)
                    .foregroundStyle(DSColor.textSecondary)
                NavigationLink(localized("AI 助手设定")) {
                    AISettingsView(embedded: true)
                        .onDisappear { if case .unavailable = model.state { model.start() } }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

#Preview("Answer") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AIWordLookupView(term: "圣者", context: "他终于突破到圣者境界，气息铺天盖地。", bookTitle: "万古神帝",
                         bookID: UUID(), onAskAI: {}, provider: AIWordLookupPreviewProvider())
    }
}

/// Answers every lookup with a fixed entry, for previews.
struct AIWordLookupPreviewProvider: LLMProviding {
    let identifier = "preview"
    let defaultModel = "preview"
    func generate(_ request: LLMGenerationRequest, model: String?) async throws -> LLMRawResponse {
        .init(content: "在这里指修炼达到的一个境界，地位远高于一般武者。\n\n## 读音\nshèng zhě\n\n## 释义\n- 道德或修为极高的人（这里的用法）\n- 宗教中的圣徒\n\n## 例句\n- 能踏入圣者之列的人，万中无一。",
              provider: identifier, model: defaultModel, finishReason: "stop")
    }
}
