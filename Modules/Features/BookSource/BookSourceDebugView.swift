import SwiftUI
import UIKit

/// 書源除錯大師 — the HTTP exchanges behind one book source.
///
/// Presented as a sheet from the book-source editor and the login sheet, so
/// `.inline` title mode and `xmark` leading (docs/design.md §2.2).
struct BookSourceDebugView: View {
    @ObservedObject private var debugger = WebCrawlerDebugger.shared
    @Environment(\.dismiss) private var dismiss
    @State private var typeFilter: WebCrawlerDebugger.LogEntry.LogType?
    @State private var showCopiedAlert = false

    private var filteredLogs: [WebCrawlerDebugger.LogEntry] {
        guard let typeFilter else { return debugger.logs.reversed() }
        return debugger.logs.reversed().filter { $0.type == typeFilter }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(localized("启用网路除错录制"), isOn: $debugger.isRecording)
                    Toggle(localized("包含规则比对"), isOn: $debugger.includesParseEvents)
                        .disabled(!debugger.isRecording)
                } header: {
                    Text(localized("录制"))
                        .foregroundStyle(DSColor.textSecondary)
                } footer: {
                    Text(localized("记下每一次请求与回应。规则比对量太大，预设不收。"))
                        .dsSectionFooter()
                }
                .interfaceSectionSurface()

                Section {
                    Picker(localized("类型"), selection: $typeFilter) {
                        Text(localized("全部")).tag(WebCrawlerDebugger.LogEntry.LogType?.none)
                        ForEach(WebCrawlerDebugger.LogEntry.LogType.allCases, id: \.self) { type in
                            Text(type.localizedName)
                                .tag(WebCrawlerDebugger.LogEntry.LogType?.some(type))
                        }
                    }
                } header: {
                    Text(localized("筛选"))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .interfaceSectionSurface()

                Section {
                    ShareLink(
                        item: BookSourceDebugExportFile(
                            filename: BookSourceDebugExportFile.filename(),
                            entries: debugger.logs
                        ),
                        preview: SharePreview(localized("书源除错大师"))
                    ) {
                        Label(localized("汇出纪录"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(debugger.logs.isEmpty)
                } header: {
                    Text(localized("操作"))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .interfaceSectionSurface()

                Section {
                    if filteredLogs.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredLogs) { entry in
                            BookSourceDebugLogRow(entry: entry)
                        }
                    }
                } header: {
                    Text(localized("纪录"))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .navigationTitle(localized("书源除错大师"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(localized("关闭"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // 匯出紀錄 is deliberately NOT here: a `ShareLink` inside a `Menu`
                    // loses its share sheet to the menu's own dismissal before iOS 18
                    // (`MenuShareLinkPresentationPolicy`). It lives in the 操作 section
                    // instead, exactly like 診斷與回報's export link. Only non-presenting
                    // actions belong in this menu.
                    Menu {
                        Button {
                            UIPasteboard.general.string = exportText
                            showCopiedAlert = true
                        } label: {
                            Label(localized("复制全部"), systemImage: "doc.on.doc")
                        }
                        Divider()
                        Button(role: .destructive) {
                            debugger.clear()
                        } label: {
                            Label(localized("清空纪录"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(localized("更多动作"))
                    .disabled(debugger.logs.isEmpty)
                }
            }
            .alert(localized("已复制"), isPresented: $showCopiedAlert) {
                Button(localized("好"), role: .cancel) {}
            } message: {
                Text(localized("除错纪录已复制到剪贴簿。"))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            UnavailableLabel(localized("没有纪录"), systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text(debugger.isRecording
                 ? localized("录制中。回到书源做一次搜索或开启章节，请求就会出现在这里。")
                 : localized("先打开上面的录制开关，再回到书源操作一次。")).foregroundStyle(DSColor.textSecondary)
        }
    }

    /// Built on demand — this is only read inside 複製全部's action closure, so the
    /// formatting cost is paid on tap and never on a layout pass. The share export
    /// renders through the same function; see `BookSourceDebugExportFile`.
    private var exportText: String {
        BookSourceDebugExportFile.render(entries: debugger.logs)
    }
}

/// Its own `View` struct so `List`/`Form` defers building the expanded detail until
/// the row scrolls in — see the note at the top of `BookSourceRowViews.swift`.
struct BookSourceDebugLogRow: View {
    let entry: WebCrawlerDebugger.LogEntry
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasDetail: Bool { entry.detail != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                Image(systemName: entry.type.symbolName)
                    .font(DSFont.footnote)
                    .foregroundStyle(entry.type.tint)
                    .accessibilityHidden(true)

                Text(entry.message)
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(isExpanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.timestamp, style: .time)
                    .font(DSFont.caption2)
                    .foregroundStyle(DSColor.textSecondary)
            }

            if let url = entry.url {
                Text(url)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.accent)
                    .lineLimit(isExpanded ? nil : 1)
            }

            if isExpanded, let detail = entry.detail {
                detailView(detail)
                    .padding(.top, DSSpacing.xs)
            }
        }
        .padding(.vertical, DSSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasDetail else { return }
            if reduceMotion {
                isExpanded.toggle()
            } else {
                withAnimation(DSAnimation.fast) { isExpanded.toggle() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.type.localizedName)，\(entry.message)")
        .accessibilityValue(entry.url ?? "")
        .accessibilityHint(hasDetail ? localized("点两下展开详细内容") : "")
        .accessibilityAddTraits(hasDetail ? .isButton : [])
    }

    @ViewBuilder
    private func detailView(_ detail: WebCrawlerDebugger.LogEntry.Detail) -> some View {
        switch detail {
        case .headers(let headers):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    Text("\(key): \(value)")
                        .font(DSFont.monospaced(size: 11))
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .body(let text), .text(let text):
            Text(text)
                .font(DSFont.monospaced(size: 11))
                .foregroundStyle(DSColor.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension WebCrawlerDebugger.LogEntry.LogType {
    var localizedName: String {
        switch self {
        case .info:       return localized("资讯")
        case .request:    return localized("请求")
        case .response:   return localized("回应")
        case .parseEvent: return localized("规则比对")
        case .error:      return localized("错误")
        }
    }

    /// SF Symbol rather than an emoji: emoji do not follow Dynamic Type or the
    /// accent tint, and VoiceOver reads them aloud as their CLDR name.
    var symbolName: String {
        switch self {
        case .info:       return "info.circle"
        case .request:    return "arrow.up.circle"
        case .response:   return "arrow.down.circle"
        case .parseEvent: return "scope"
        case .error:      return "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .info:       return DSColor.textSecondary
        case .request:    return DSColor.accent
        case .response:   return DSColor.success
        case .parseEvent: return DSColor.warning
        case .error:      return DSColor.destructive
        }
    }
}

#Preview {
    BookSourceDebugView()
}
