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
                ThemedLabeledContent(localized("章节目录"), value: "\(adapter.manifest.chapters.count)")
                ThemedLabeledContent(localized("本机可用正文"), value: "\(adapter.manifest.chapters.count - missingChapters.count) / \(adapter.manifest.chapters.count)")
                ThemedLabeledContent(localized("已索引章节"), value: "\(service.indexedChapterCounts[adapter.chunkBookID] ?? 0)")
                ThemedLabeledContent(localized("检索索引"), value: indexDescription)
                if !missingChapters.isEmpty {
                    DisclosureGroup {
                        ForEach(missingChapters, id: \.order) { chapter in
                            ThemedLabeledContent(String(format: localized("第 %d 章"), chapter.order + 1), value: availability(chapter.status))
                        }
                    } label: {
                        ThemedLabeledContent(localized("缺少正文的章节"), value: "\(missingChapters.count)")
                    }
                }
            } header: {
                Text(localized("本书内容"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("未下载或抽取失败的章节不在搜寻范围，也不会自动下载。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
            Section {
                ThemedLabeledContent(localized("每题模型呼叫上限"), value: "\(AIQuestionBudget().maximumModelCalls)")
                ThemedLabeledContent(localized("每题搜寻词上限"), value: "\(AIQuestionBudget().maximumQueries)")
            } header: {
                Text(localized("问答预算"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("每次模型呼叫都可能由服务商计费。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
            Section {
                Toggle(localized("下一次请求保留敏感诊断内容"), isOn: $diagnostics.captureNextRequestContent)
                Toggle(localized("汇出 messages 与读者输入"), isOn: $includeMessages)
                Toggle(localized("汇出检索原文"), isOn: $includeEvidence)
                Toggle(localized("汇出模型回复与自评"), isOn: $includeResponse)
                if let trace = diagnostics.latest, trace.bookID == adapter.chunkBookID {
                    ThemedLabeledContent(localized("诊断请求"), value: trace.requestID.uuidString)
                }
                Button(localized("汇出本机诊断")) { export() }
                    .disabled(diagnostics.latest?.bookID != adapter.chunkBookID)
                if let exportError {
                    Label(exportError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DSColor.destructive)
                }
            } header: {
                Text(localized("诊断汇出"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("预设只保存 metadata；汇出只含勾选内容并遮蔽凭证、帐号与网址，不会自动上传。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("AI 状态与诊断"))
        .toolbarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "ShuYue-AI-diagnostics") { result in
            if case .failure = result { exportError = localized("诊断汇出失败") }
        }
    }
    private var indexDescription: String {
        switch service.indexState[adapter.chunkBookID] ?? .idle {
        case .idle: return localized("尚未建立")
        case .building: return localized("建立中…")
        case let .ready(count): return String(format: localized("已索引 %d 个片段"), count)
        case let .failed(message): return message
        }
    }
    private func availability(_ status: AISourceManifest.Availability) -> String {
        switch status {
        case .available: return localized("正文已取得")
        case .notDownloaded: return localized("尚未下载")
        case .extractionFailed: return localized("正文抽取失败")
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
        } catch { exportError = localized("诊断汇出失败") }
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
