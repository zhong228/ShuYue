import SwiftUI
import UniformTypeIdentifiers

// MARK: - Add Book Entry
struct AddBookView: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedTab = 0

    @ObservedObject private var gs = GlobalSettings.shared

    var body: some View {
        NavigationStack {
            AdaptiveSheetContainer(maxWidth: DSLayout.readableListWidth) {
                VStack(spacing: 0) {
                    Picker(localized("方式"), selection: $selectedTab) {
                        Text(localized("汇入文件")).tag(0)
                        Text(localized("网址汇入")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    if selectedTab == 0 {
                        FileImportTab(onDismiss: { presentationMode.wrappedValue.dismiss() })
                            .environmentObject(store)
                    } else {
                        URLImportTab(onDismiss: { presentationMode.wrappedValue.dismiss() })
                            .environmentObject(store)
                    }
                    Spacer()
                }
            }
            .navigationTitle(localized("添加书籍"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .bookshelf)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Label(localized("取消"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel(localized("取消"))
                }
            }
        }
    }
}

// MARK: - File Import Tab
struct FileImportTab: View {
    @EnvironmentObject var store: BookStore
    var onDismiss: () -> Void
    @State private var showFilePicker = false
    @State private var importTask: Task<Void, Never>?
    @State private var isLoading = false
    @State private var currentFile = ""
    @State private var completedCount = 0
    @State private var totalCount = 0
    @State private var errorMsg: String?

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.xl) {
                HintCard(
                    icon: "doc.text", title: localized("支援格式：TXT / Markdown / JSON / EPUB / PDF / CBZ / ZIP / 音讯"),
                    detail: localized("支援纯文字（.txt / .md / .markdown / .json）、电子书（.epub）、PDF（.pdf）、本地漫画（.cbz / .zip）与音讯（.mp3 / .m4a / .m4b / .aac / .flac / .wav）格式。选取后系统自动识别内容。"))

                Button {
                    showFilePicker = true
                } label: {
                    VStack(spacing: DSSpacing.md) {
                        Image(systemName: "folder.badge.plus")
                            .font(DSFont.fixed(size: 44)).foregroundColor(DSColor.accent)
                            .accessibilityHidden(true)
                        Text(localized("点击选取 TXT / EPUB / PDF / 漫画 / 音讯文件"))
                            .font(DSFont.headline).foregroundColor(DSColor.accent)
                        Text(localized("从文件 App、iCloud、本机储存等选取"))
                            .font(DSFont.caption).foregroundColor(DSColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity).padding(DSSpacing.xxl)
                    .background(DSColor.accentLight)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                DSColor.accent.opacity(0.4),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                }
                .buttonStyle(.plain)
                .accessibilityHint(localized("选取多本书籍"))
                .disabled(isLoading)

                if isLoading {
                    ProgressView(value: Double(completedCount), total: Double(max(1, totalCount))) {
                        Text(currentFile).font(DSFont.caption).foregroundColor(DSColor.textSecondary)
                    }
                    .accessibilityValue("\(completedCount) / \(totalCount)")
                }
                if let errorMsg {
                    Text(localized("汇入失败：") + errorMsg)
                        .font(DSFont.caption).foregroundColor(DSColor.destructive).padding()
                }
            }
            .padding()
        }
        .softScrollEdges()
        .sheet(isPresented: $showFilePicker) {
            UIDocumentPickerBridge(
                onPick: { urls in
                    guard !urls.isEmpty else { return }
                    isLoading = true
                    errorMsg = nil
                    completedCount = 0
                    totalCount = urls.count
                    importTask = Task { @MainActor in
                        defer { isLoading = false }
                        do {
                            let imported = try await LocalBookImportService.importBooks(at: urls, store: store) { index, filename in
                                completedCount = index
                                currentFile = filename
                            }
                            completedCount = urls.count
                            if imported.failures.isEmpty { onDismiss() }
                            else { errorMsg = imported.failures.joined(separator: "\n") }
                        } catch is CancellationError {
                        } catch {
                            errorMsg = error.localizedDescription
                        }
                    }
                },
                onCancel: { }
            )
        }
        .interactiveDismissDisabled(isLoading)
        .onDisappear { importTask?.cancel() }
    }
}

// MARK: - URL Import Tab
struct URLImportTab: View {
    @EnvironmentObject var store: BookStore
    @Environment(\.appDependencies) private var dependencies
    var onDismiss: () -> Void
    @State private var urlInput = ""
    @State private var titleInput = ""
    @State private var authorInput = ""
    @State private var fetchedContent: String? = nil
    @State private var fetchedPreviewText: String? = nil
    @State private var detectedTOCRefs: [OnlineChapterRef] = []
    @State private var isLoading = false
    @State private var errorMsg: String? = nil
    @ObservedObject private var gs = GlobalSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HintCard(
                    icon: "globe",
                    title: localized("网址汇入"),
                    detail: localized("输入小说网页网址，系统抓取页面文字。建议选用有纯文字章节页面的网站。"))

                VStack(alignment: .leading, spacing: 8) {
                    Label(localized("网址"), systemImage: "link")
                        .font(DSFont.caption).foregroundColor(DSColor.textSecondary)
                    HStack {
                        TextField("https://...", text: $urlInput)
                            .disableAutocorrection(true)
                        if !urlInput.isEmpty {
                            Button {
                                urlInput = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(DSColor.textTertiary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if fetchedContent != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(localized("书名"), systemImage: "text.book.closed")
                            .font(DSFont.caption).foregroundColor(DSColor.textSecondary)
                        TextField(localized("书名（必填）"), text: $titleInput)
                            .padding(12).background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Label(localized("作者"), systemImage: "person")
                            .font(DSFont.caption).foregroundColor(DSColor.textSecondary)
                        TextField(localized("作者（选填）"), text: $authorInput)
                            .padding(12).background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        if let preview = fetchedPreviewText {
                            Text(String(format: localized("已抓取约 %d 字"), preview.count))
                                .font(DSFont.caption).foregroundColor(DSColor.textSecondary)
                        }
                        if !detectedTOCRefs.isEmpty {
                            Text(
                                String(
                                    format: localized("侦测到章节目录：%d 章，将以线上书模式导入"),
                                    detectedTOCRefs.count))
                                .font(DSFont.caption)
                                .foregroundColor(DSColor.textSecondary)
                        }
                    }
                }

                if isLoading { ProgressView(localized("正在抓取页面…")) }
                if let err = errorMsg {
                    Text(err).font(DSFont.caption).foregroundColor(.red).padding(.horizontal)
                }

                if fetchedContent == nil {
                    Button {
                        fetchURL()
                    } label: {
                        Label(localized("抓取页面"), systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity).padding()
                            .background(DSColor.accent).foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                    }
                    .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                } else {
                    Button {
                        saveWebBook()
                    } label: {
                        Label(localized("加入书架"), systemImage: "books.vertical")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.green).foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                    }
                    .disabled(titleInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
        }
        .softScrollEdges()
    }

    private func fetchURL() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            errorMsg = localized("网址格式不正确")
            return
        }
        isLoading = true
        errorMsg = nil
        detectedTOCRefs = []

        Task {
            do {
                let html = try await dependencies.webContentFetcher.fetchHTML(
                    url: url,
                    method: "GET",
                    body: nil,
                    headers: [:],
                    baseURL: url.absoluteString,
                    bodyCharset: nil
                )
                let text = WebNovelParser.extractContent(html: html, pageURL: url.absoluteString)
                let refs = WebNovelParser.parseTOCRefs(html: html, pageURL: url.absoluteString)

                await MainActor.run {
                    isLoading = false
                    if text.count < 120 && refs.isEmpty {
                        errorMsg = localized("抓取到的文字太少，网站可能不支援直接抓取")
                        return
                    }
                    fetchedContent = html
                    fetchedPreviewText = text.isEmpty ? html.strippedHTML : text
                    detectedTOCRefs = refs
                    if titleInput.isEmpty,
                       let r = html.range(
                        of: "(?<=<title>)[^<]+(?=</title>)",
                        options: .regularExpression)
                    {
                        titleInput = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMsg = localized("抓取失败：") + error.localizedDescription
                }
            }
        }
    }

    private func saveWebBook() {
        guard let content = fetchedContent else { return }
        let title = titleInput.trimmingCharacters(in: .whitespaces)
        let author =
            authorInput.trimmingCharacters(in: .whitespaces).isEmpty
            ? localized("网路书籍") : authorInput

        if !detectedTOCRefs.isEmpty {
            _ = store.addWebBrowsedBook(
                name: title,
                author: author,
                sourceURL: urlInput.trimmingCharacters(in: .whitespacesAndNewlines),
                chapters: detectedTOCRefs
            )
            onDismiss()
            return
        }

        _ = try? store.importWeb(
            content: content,
            title: title,
            author: author,
            sourceURL: urlInput,
            format: .html
        )
        onDismiss()
    }
}

// MARK: - Hint Card
struct HintCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(DSFont.title2).foregroundColor(DSColor.accent).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Text(detail).font(DSFont.caption).foregroundColor(DSColor.textSecondary)
            }
            Spacer()
        }
        .padding()
        .background(DSColor.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
    }
}
#Preview{
        AddBookView()
            .environmentObject(BookStore())
}
