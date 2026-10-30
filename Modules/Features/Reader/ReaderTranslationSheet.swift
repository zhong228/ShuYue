import SwiftUI

/// 整章翻譯's controls for the book being read: how translations show, into which language,
/// and where the chapter on screen stands.
struct ReaderTranslationSheet: View {
    @Binding var presentation: ReaderTranslationPresentation
    let bookID: UUID
    /// The chapter on screen and its own text, when it is laid out.
    let chapter: Int
    let chapterText: String?
    /// Translates what the chapter on screen is missing (and retries a failed run).
    let onTranslateChapter: () -> Void
    @ObservedObject private var service = AIChapterTranslationService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsClear = false
    @State private var clearError: String?

    private var currentChapter: AIChapterTranslationService.Chapter {
        .init(book: bookID, spine: chapter, language: presentation.language)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(localized("显示方式"), selection: $presentation.mode) {
                        Text(localized("关闭")).tag(ReaderTranslationPresentation.Mode.off)
                        Text(localized("双语对照")).tag(ReaderTranslationPresentation.Mode.bilingual)
                        Text(localized("只看译文")).tag(ReaderTranslationPresentation.Mode.translationOnly)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(localized("显示方式"))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .interfaceSectionSurface()

                if presentation.isActive {
                    Section {
                        Picker(localized("翻译成"), selection: $presentation.language) {
                            ForEach(AIAnswerLanguage.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                    .interfaceSectionSurface()
                    chapterSection
                    serviceSection
                }

                Section {
                    Button(localized("清除本书译文"), role: .destructive) { confirmsClear = true }
                } footer: {
                    if let clearError {
                        Text(clearError).dsSectionFooter()
                    }
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .themedAppSurface(for: .settings)
            .navigationTitle(localized("整章翻译"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(localized("关闭"))
                }
            }
            .confirmationDialog(localized("清除本书的所有译文？"), isPresented: $confirmsClear, titleVisibility: .visible) {
                Button(localized("清除译文"), role: .destructive) { clear() }
                Button(localized("取消"), role: .cancel) {}
            } message: {
                Text(localized("译文会删除，翻译也会关闭；之后再开启要重新翻译。"))
            }
        }
    }

    @ViewBuilder private var chapterSection: some View {
        Section {
            switch service.runs[currentChapter] {
            case let .running(completed, total):
                ProgressView(value: Double(completed), total: Double(max(total, 1))) {
                    Text(localized("翻译中…"))
                        .foregroundStyle(DSColor.textPrimary)
                } currentValueLabel: {
                    Text(verbatim: "\(completed)/\(total)")
                        .foregroundStyle(DSColor.textSecondary)
                }
            case .finished:
                Label(localized("本章已翻译"), systemImage: "checkmark.circle")
                    .foregroundStyle(DSColor.textPrimary)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(DSColor.destructive)
                Button(localized("重试"), action: onTranslateChapter)
            case nil:
                if let chapterText {
                    if service.pendingBatchCount(book: bookID, language: presentation.language, text: chapterText) == 0 {
                        Label(localized("本章已翻译"), systemImage: "checkmark.circle")
                            .foregroundStyle(DSColor.textPrimary)
                    } else {
                        Button(localized("翻译本章"), action: onTranslateChapter)
                    }
                } else {
                    Text(localized("本章还在载入"))
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        } header: {
            Text(localized("本章"))
                .foregroundStyle(DSColor.textSecondary)
        }
        .interfaceSectionSurface()
    }

    @ViewBuilder private var serviceSection: some View {
        switch service.service() {
        case let .success(active):
            Section {
                ThemedLabeledContent(localized("生成服务"), value: active.name)
                ThemedLabeledContent(localized("生成模型"), value: active.model)
            } footer: {
                Text(localized("会翻译你读到的章节和下一章，约每 2,000 字一次模型呼叫；原文、划线与阅读进度不受影响。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        case let .failure(reason):
            Section {
                Text(reason.message)
                    .foregroundStyle(DSColor.textSecondary)
                NavigationLink(localized("AI 助手设定")) { AISettingsView(embedded: true) }
            }
            .interfaceSectionSurface()
        }
    }

    private func clear() {
        presentation.mode = .off
        Task {
            do {
                try await service.clear(book: bookID)
                clearError = nil
            } catch {
                AppLogger.error("Clearing a book's translations failed", error: error, context: ["book": bookID.uuidString])
                clearError = error.localizedDescription
            }
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ReaderTranslationSheet(presentation: .constant(.init(mode: .bilingual, language: .traditionalChinese)),
                               bookID: UUID(), chapter: 0, chapterText: "It was a bright cold day in April.",
                               onTranslateChapter: {})
    }
}
