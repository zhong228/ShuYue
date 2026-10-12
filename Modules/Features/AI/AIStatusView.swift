import SwiftUI
import UniformTypeIdentifiers

struct AIStatusView: View {
    let adapter: AIBookContentAdapter
    @ObservedObject private var service = AIAssistantService.shared
    @ObservedObject private var diagnostics = AIDiagnosticStore.shared
    @State private var includeMessages = false
    @State private var includeEvidence = false
    @State private var includeResponse = false
    @State private var document: AIDiagnosticDocument?
    @State private var exporting = false
    @State private var exportError: String?

    private var missingChapters: [AISourceManifest.Chapter] {
        adapter.manifest.chapters.filter { $0.status != .available }
    }

    var body: some View {
        Form {
            Section {
                ThemedLabeledContent(localized("章節目錄"), value: "\(adapter.manifest.chapters.count)")
                ThemedLabeledContent(localized("本機可用正文"), value: "\(adapter.manifest.chapters.count - missingChapters.count) / \(adapter.manifest.chapters.count)")
                ThemedLabeledContent(localized("已索引章節"), value: "\(service.indexedChapterCounts[adapter.chunkBookID] ?? 0)")
                ThemedLabeledContent(localized("檢索索引"), value: indexDescription)
                if !missingChapters.isEmpty {
                    DisclosureGroup {
                        ForEach(missingChapters, id: \.order) { chapter in
                            ThemedLabeledContent(String(format: localized("第 %d 章"), chapter.order + 1), value: availability(chapter.status))
                        }
                    } label: {
                        ThemedLabeledContent(localized("缺少正文的章節"), value: "\(missingChapters.count)")
                    }
                }
            } header: {
                Text(localized("本書內容"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("未下載或抽取失敗的章節不在搜尋範圍，也不會自動下載。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
            Section {
                ThemedLabeledContent(localized("每題模型呼叫上限"), value: "\(AIQuestionBudget().maximumModelCalls)")
                ThemedLabeledContent(localized("每題搜尋詞上限"), value: "\(AIQuestionBudget().maximumQueries)")
            } header: {
                Text(localized("問答預算"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("每次模型呼叫都可能由服務商計費。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
            Section {
                Toggle(localized("下一次請求保留敏感診斷內容"), isOn: $diagnostics.captureNextRequestContent)
                Toggle(localized("匯出 messages 與讀者輸入"), isOn: $includeMessages)
                Toggle(localized("匯出檢索原文"), isOn: $includeEvidence)
                Toggle(localized("匯出模型回覆與自評"), isOn: $includeResponse)
                if let trace = diagnostics.latest, trace.bookID == adapter.chunkBookID {
                    ThemedLabeledContent(localized("診斷請求"), value: trace.requestID.uuidString)
                }
                Button(localized("匯出本機診斷")) { export() }
                    .disabled(diagnostics.latest?.bookID != adapter.chunkBookID)
                if let exportError {
                    Label(exportError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DSColor.destructive)
                }
            } header: {
                Text(localized("診斷匯出"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("預設只保存 metadata；匯出只含勾選內容並遮蔽憑證、帳號與網址，不會自動上傳。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("AI 狀態與診斷"))
        .toolbarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "MoYue-AI-diagnostics") { result in
            if case .failure = result { exportError = localized("診斷匯出失敗") }
        }
    }
    private var indexDescription: String {
        switch service.indexState[adapter.chunkBookID] ?? .idle {
        case .idle: return localized("尚未建立")
        case .building: return localized("建立中…")
        case let .ready(count): return String(format: localized("已索引 %d 個片段"), count)
        case let .failed(message): return message
        }
    }
    private func availability(_ status: AISourceManifest.Availability) -> String {
        switch status {
        case .available: return localized("正文已取得")
        case .notDownloaded: return localized("尚未下載")
        case .extractionFailed: return localized("正文抽取失敗")
        case .unsupported: return localized("格式不支援正文抽取")
        }
    }
    private func export() {
        var categories = Set<String>()
        if includeMessages { categories.insert("messages") }
        if includeEvidence { categories.insert("evidence") }
        if includeResponse { categories.formUnion(["response", "assessment"]) }
        do {
            guard let trace = diagnostics.latest, trace.bookID == adapter.chunkBookID else { return }
            document = AIDiagnosticDocument(data: try trace.export(including: categories))
            exporting = true
        } catch { exportError = localized("診斷匯出失敗") }
    }
}
struct AIDiagnosticDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
#Preview {
    NavigationStack { AIStatusView(adapter: .init(bookID: UUID(), chapters: [], textForChapter: { _ in nil })) }
}
