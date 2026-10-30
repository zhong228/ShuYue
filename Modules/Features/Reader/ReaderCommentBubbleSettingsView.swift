import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ReaderCommentBubbleSettingsView: View {
    @ObservedObject private var settings = GlobalSettings.shared
    @StateObject private var readerConfig = ReaderConfig.shared
    @State private var showingSVGImporter = false
    @State private var showingSVGExporter = false
    @State private var editorDraft: CommentBubbleStyleEditorDraft?
    @State private var stylePendingDeletion: ReaderCommentBubbleCustomStyle?
    @State private var importAlert: BubbleImportAlert?

    var body: some View {
        Form {
            Section(header: Text(localized("气泡样式")).foregroundStyle(DSColor.textSecondary)) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DSSpacing.sm) {
                        ForEach([
                            ReaderCommentBubblePresetMode.builtin,
                            ReaderCommentBubblePresetMode.square,
                        ]) { mode in
                            builtinStyleButton(mode: mode)
                        }

                        ForEach(settings.commentBubbleCustomStyles) { style in
                            customStyleButton(style: style)
                        }
                    }
                }
                .padding(.vertical, DSSpacing.sm)
            }
            .interfaceSectionSurface()

            Section {
                Toggle(localized("优先使用选取的气泡样式"), isOn: prioritizeSelectedBubbleBinding)
            } header: {
                Text(localized("显示偏好"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("开启后优先使用选取的气泡样式；关闭后依书源提供的 SVG 显示。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section(header: Text(localized("管理")).foregroundStyle(DSColor.textSecondary)) {
                Button(action: openNewStyleEditor) {
                    Label(localized("新建样式"), systemImage: "plus.circle")
                }

                Button {
                    showingSVGImporter = true
                } label: {
                    Label(localized("汇入样式"), systemImage: "square.and.arrow.down")
                }

                Button {
                    showingSVGExporter = true
                } label: {
                    Label(localized("汇出当前样式"), systemImage: "square.and.arrow.up")
                }

                if let activeCustomStyle {
                    Button {
                        openStyleEditor(for: activeCustomStyle)
                    } label: {
                        Label(localized("编辑目前样式"), systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        stylePendingDeletion = activeCustomStyle
                    } label: {
                        Label(localized("删除目前样式"), systemImage: "trash")
                    }
                }
            }
            .interfaceSectionSurface()

            Section(header: Text(localized("整体大小")).foregroundStyle(DSColor.textSecondary)) {
                BubbleSliderRow(
                    title: localized("当前样式大小"),
                    valueText: String(format: "%.2f×", settings.commentBubbleScale),
                    value: bubbleScaleBinding,
                    range: GlobalSettings.commentBubbleScaleRange,
                    step: 0.05
                )
                Text(localized("这里调整目前选取气泡样式的整体大小。"))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("气泡设定"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .sheet(item: $editorDraft) { draft in
            CommentBubbleStyleEditorView(
                draft: draft,
                onSave: saveEditorDraft
            )
            .presentationDetents([.large])
        }
        .fileImporter(
            isPresented: $showingSVGImporter,
            allowedContentTypes: Self.svgContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleSVGImport
        )
        .fileExporter(
            isPresented: $showingSVGExporter,
            document: CommentBubbleSVGDocument(svg: currentStyleSVG),
            contentType: Self.svgContentType,
            defaultFilename: exportFilename,
            onCompletion: handleSVGExport
        )
        .alert(
            localized("删除目前样式？"),
            isPresented: Binding(
                get: { stylePendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        stylePendingDeletion = nil
                    }
                }
            ),
            presenting: stylePendingDeletion
        ) { style in
            Button(localized("删除目前样式"), role: .destructive) {
                deleteCustomStyle(style)
            }
            Button(localized("取消"), role: .cancel) {}
        } message: { style in
            Text(
                String(
                    format: localized("「%@」会被永久删除，此操作无法复原。"),
                    style.name
                )
            )
        }
        .alert(item: $importAlert) { alert in
            Alert(
                title: Text(localized(alert.titleKey)),
                message: Text(alert.message),
                dismissButton: .default(Text(localized("确定")))
            )
        }
    }

    private func builtinStyleButton(mode: ReaderCommentBubblePresetMode) -> some View {
        let title = localized(mode.titleKey)
        let svg = CommentBubbleSVGRecognizer.templateSVG(for: mode, customSVG: "")
        let isSelected = settings.commentBubblePresetMode == mode

        return styleButton(
            title: title,
            svg: svg,
            isSelected: isSelected
        ) {
            selectBuiltinStyle(mode)
        }
    }

    private func customStyleButton(style: ReaderCommentBubbleCustomStyle) -> some View {
        let trimmedName = style.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedName.isEmpty ? localized("自订 SVG") : trimmedName
        let isSelected = settings.commentBubblePresetMode == .custom
            && settings.commentBubbleSelectedCustomStyleID == style.id

        // For bubble.json styles, substitute the literal `${color}` so the picker
        // preview reflects the actual rendered look (day normal colour for "99").
        // Legacy SVG previews render unchanged.
        let previewSVG: String
        if style.usesColorTemplate {
            let hex = style.resolvedColorHex(forCount: "99", isNight: false)
            previewSVG = CommentBubbleSVGRecognizer.materializeColorTemplate(
                style.svg,
                colorHex: hex
            )
        } else {
            previewSVG = style.svg
        }

        return styleButton(
            title: title,
            svg: previewSVG,
            isSelected: isSelected
        ) {
            settings.selectCommentBubbleCustomStyle(id: style.id)
            settings.commentBubbleFollowsSourceSVG = false
        }
    }

    private func styleButton(
        title: String,
        svg: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: DSSpacing.sm) {
                if let preview = previewImage(svg: svg) {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(height: DSSpacing.xl)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "text.bubble")
                        .font(DSFont.title2)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(DSFont.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isSelected ? DSColor.accent : DSColor.textPrimary)
            .frame(
                minWidth: DSLayout.readerBubblePreviewTileWidth,
                maxWidth: DSLayout.readerBubblePreviewTileWidth,
                minHeight: DSLayout.readerBubblePreviewHeight
            )
            .background(isSelected ? DSColor.accentLight : DSColor.surfaceTertiary)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .stroke(
                        isSelected ? DSColor.accent : DSColor.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func previewImage(svg: String) -> UIImage? {
        guard let bubble = CommentBubbleSVGRecognizer.recognizeUserTemplate(svg) else {
            return nil
        }
        return CommentBubbleSVGRecognizer.draw(
            svg: bubble.replacingDisplayText(with: "99"),
            pointSize: 34,
            themeTextColor: .label,
            textFace: .reader
        )
    }

    private var activeCustomStyle: ReaderCommentBubbleCustomStyle? {
        guard settings.commentBubblePresetMode == .custom else { return nil }
        return settings.commentBubbleSelectedCustomStyle
    }

    private var prioritizeSelectedBubbleBinding: Binding<Bool> {
        Binding(
            get: { !settings.commentBubbleFollowsSourceSVG },
            set: { prioritizesSelectedStyle in
                settings.commentBubbleFollowsSourceSVG = !prioritizesSelectedStyle
            }
        )
    }

    private var bubbleScaleBinding: Binding<Double> {
        Binding(
            get: { settings.commentBubbleScale },
            set: { value in
                settings.commentBubbleScale = value
                settings.commentBubbleFollowsSourceSVG = false
            }
        )
    }

    private var currentStyleSVG: String {
        CommentBubbleSVGRecognizer.templateSVG(
            for: settings.commentBubblePresetMode,
            customSVG: settings.commentBubbleSelectedCustomStyle?.svg ?? ""
        )
    }

    private static let svgContentType = UTType(filenameExtension: "svg") ?? .data

    private static let svgContentTypes: [UTType] = [
        svgContentType,
        .plainText,
        .data,
    ]

    private var exportFilename: String {
        let candidate: String
        switch settings.commentBubblePresetMode {
        case .builtin, .square:
            candidate = localized(settings.commentBubblePresetMode.titleKey)
        case .custom:
            candidate = settings.commentBubbleSelectedCustomStyle?.name ?? localized("自订 SVG")
        }
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedCandidate.isEmpty ? "comment-bubble" : trimmedCandidate) + ".svg"
    }

    private func selectBuiltinStyle(_ mode: ReaderCommentBubblePresetMode) {
        switch mode {
        case .builtin:
            settings.selectCommentBubbleBuiltinStyle()
        case .square:
            settings.selectCommentBubbleSquareStyle()
        case .custom:
            return
        }
        settings.commentBubbleFollowsSourceSVG = false
    }

    private func openNewStyleEditor() {
        editorDraft = CommentBubbleStyleEditorDraft(
            styleID: nil,
            titleKey: "新建样式",
            name: "",
            svg: ""
        )
    }

    private func openStyleEditor(for style: ReaderCommentBubbleCustomStyle) {
        editorDraft = CommentBubbleStyleEditorDraft(
            styleID: style.id,
            titleKey: "编辑样式",
            name: style.name,
            svg: style.svg
        )
    }

    private func saveEditorDraft(
        styleID: UUID?,
        name: String,
        svg: String
    ) -> String? {
        let trimmedSVG = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validationMessage = validationMessage(for: trimmedSVG) {
            return validationMessage
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? localized("自订 SVG") : trimmedName
        settings.upsertCommentBubbleCustomStyle(
            ReaderCommentBubbleCustomStyle(
                id: styleID ?? UUID(),
                name: resolvedName,
                svg: trimmedSVG
            )
        )
        settings.commentBubbleFollowsSourceSVG = false
        return nil
    }

    private func deleteCustomStyle(_ style: ReaderCommentBubbleCustomStyle) {
        settings.deleteCommentBubbleCustomStyle(id: style.id)
        stylePendingDeletion = nil
    }

    private func handleSVGImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)

            //分流一：bubble.json 包裝的氣泡。把 svgTemplate（含 ${num} / ${color}
            //占位符）原樣存進 custom style，附帶日/夜 × 一般/強調四檔顏色與 sizeScale。
            if let style = ReaderCommentBubbleCustomStyle.fromBubblePackage(data) {
                let trimmedSVGForValidation = style.svg
                if let validationMessage = validationMessage(for: trimmedSVGForValidation) {
                    showInvalidSVGAlert(message: validationMessage)
                    return
                }
                settings.upsertCommentBubbleCustomStyle(style)
                if let scale = style.sizeScale {
                    settings.commentBubbleScale = GlobalSettings.sanitizedCommentBubbleScale(scale)
                }
                settings.commentBubbleFollowsSourceSVG = false
                importAlert = BubbleImportAlert(
                    titleKey: "SVG 汇入成功",
                    message: localized("已套用自订段评气泡 SVG。")
                )
                return
            }

            // 分流二：純 SVG 文字。
            guard let svg = String(data: data, encoding: .utf8) else {
                showInvalidSVGAlert(message: localized("档案不是可读取的 SVG。"))
                return
            }

            let trimmedSVG = svg.trimmingCharacters(in: .whitespacesAndNewlines)
            if let validationMessage = validationMessage(for: trimmedSVG) {
                showInvalidSVGAlert(message: validationMessage)
                return
            }

            let fileName = url.deletingPathExtension().lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let styleName = fileName.isEmpty ? localized("自订 SVG") : fileName
            settings.upsertCommentBubbleCustomStyle(
                ReaderCommentBubbleCustomStyle(name: styleName, svg: trimmedSVG)
            )
            settings.commentBubbleFollowsSourceSVG = false
            importAlert = BubbleImportAlert(
                titleKey: "SVG 汇入成功",
                message: localized("已套用自订段评气泡 SVG。")
            )
        } catch {
            importAlert = BubbleImportAlert(
                titleKey: "SVG 汇入失败",
                message: error.localizedDescription
            )
        }
    }

    private func handleSVGExport(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            importAlert = BubbleImportAlert(
                titleKey: "操作失败",
                message: error.localizedDescription
            )
        }
    }

    private func validationMessage(for svg: String) -> String? {
        if svg.utf8.count > CommentBubbleSVGRecognizer.maximumUserTemplateSVGByteCount {
            return String(
                format: localized("SVG 档案过大，请使用小于 %d KB 的气泡样式。"),
                CommentBubbleSVGRecognizer.maximumUserTemplateSVGByteCount / 1024
            )
        }
        guard svg.lowercased().contains("<svg") else {
            return localized("档案不是可读取的 SVG。")
        }
        guard CommentBubbleSVGRecognizer.recognizeUserTemplate(svg) != nil else {
            return localized("这个 SVG 没有可绘制的内容，无法作为段评气泡。")
        }
        return nil
    }

    private func showInvalidSVGAlert(message: String) {
        importAlert = BubbleImportAlert(
            titleKey: "SVG 汇入失败",
            message: message
        )
    }

}

private struct CommentBubbleStyleEditorDraft: Identifiable {
    let id = UUID()
    let styleID: UUID?
    let titleKey: String
    let name: String
    let svg: String
}

private struct CommentBubbleStyleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var nameDraft: String
    @State private var svgDraft: String
    @State private var validationMessage: String?

    let draft: CommentBubbleStyleEditorDraft
    let onSave: (UUID?, String, String) -> String?

    init(
        draft: CommentBubbleStyleEditorDraft,
        onSave: @escaping (UUID?, String, String) -> String?
    ) {
        self.draft = draft
        self.onSave = onSave
        _nameDraft = State(initialValue: draft.name)
        _svgDraft = State(initialValue: draft.svg)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(localized("样式名称")).foregroundStyle(DSColor.textSecondary)) {
                    TextField(localized("样式名称"), text: $nameDraft)
                }
                .interfaceSectionSurface()

                Section(header: Text(localized("SVG / TXT")).foregroundStyle(DSColor.textSecondary)) {
                    TextEditor(text: $svgDraft)
                        .font(DSFont.monospaced())
                        .frame(minHeight: DSLayout.readerSVGEditorHeight)

                    Button {
                        if let pastedSVG = UIPasteboard.general.string {
                            svgDraft = pastedSVG
                        }
                    } label: {
                        Label(localized("从剪贴簿贴上 SVG"), systemImage: "doc.on.clipboard")
                    }
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .navigationTitle(localized(draft.titleKey))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(localized("取消"))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let message = onSave(draft.styleID, nameDraft, svgDraft) {
                            validationMessage = message
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(svgDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(localized("储存"))
                }
            }
            .alert(
                localized("SVG 汇入失败"),
                isPresented: Binding(
                    get: { validationMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            validationMessage = nil
                        }
                    }
                )
            ) {
                Button(localized("确定"), role: .cancel) {}
            } message: {
                Text(validationMessage ?? "")
            }
        }
    }
}

private struct BubbleSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                Text(valueText)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
            }

            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, DSSpacing.xs)
    }
}

private struct BubbleImportAlert: Identifiable {
    let id = UUID()
    let titleKey: String
    let message: String
}

private struct CommentBubbleSVGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "svg") ?? .data] }
    static var writableContentTypes: [UTType] { [UTType(filenameExtension: "svg") ?? .data] }

    var svg: String

    init(svg: String) {
        self.svg = svg
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        svg = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(svg.utf8))
    }
}

#Preview {
    NavigationStack {
        ReaderCommentBubbleSettingsView()
    }
}
