import SwiftUI

/// 查看詳情 — read-only summary of one book source.
///
/// Deliberately not an editor: it answers "why is this source behaving like this" without the
/// risk of a stray edit. Everything shown is derived from the stored `BookSource` plus the last
/// validation result, so it works offline and never re-fetches.
struct BookSourceInfoSheet: View {
    let source: BookSource
    let validation: SourceValidationSummary?

    @Environment(\.dismiss) private var dismiss

    private var sourceTypeText: String {
        switch source.bookSourceType {
        case 1: return localized("音频")
        case 2: return localized("图片")
        case 3: return localized("文件")
        default: return localized("文本")
        }
    }

    private var lastUpdateText: String? {
        guard source.lastUpdateTime > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(source.lastUpdateTime) / 1000)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    infoRow(localized("书源名称"), value: displayName)
                    infoRow(
                        localized("分组"),
                        value: source.bookSourceGroup.isEmpty
                            ? localized("默认分组") : source.bookSourceGroup)
                    infoRow(localized("网址"), value: source.bookSourceUrl, monospaced: true)
                    infoRow(localized("类型"), value: sourceTypeText)
                }
                .interfaceSectionSurface()

                Section {
                    infoRow(
                        localized("状态"),
                        value: localized(source.enabled ? "已启用" : "已停用"))
                    infoRow(
                        localized("支持发现"),
                        value: localized(supportsExplore ? "是" : "否"))
                    if let validation {
                        infoRow(localized("验证结果"), value: validationText(validation))
                    }
                    infoRow(localized("响应时间"), value: "\(source.respondTime) ms")
                    if let lastUpdateText {
                        infoRow(localized("最后更新"), value: lastUpdateText)
                    }
                    if !source.concurrentRate.isEmpty {
                        infoRow(localized("并发限制"), value: source.concurrentRate)
                    }
                    if !source.loginUrl.isEmpty {
                        infoRow(localized("登入网址"), value: source.loginUrl, monospaced: true)
                    }
                }
                .interfaceSectionSurface()

                Section {
                    ruleRow(localized("搜索规则"), present: !source.searchUrl.isEmpty)
                    ruleRow(localized("发现规则"), present: !source.exploreUrl.isEmpty)
                    ruleRow(localized("详情规则"), present: !source.ruleBookInfo.tocUrl.isEmpty)
                    ruleRow(localized("目录规则"), present: !source.ruleToc.chapterList.isEmpty)
                    ruleRow(localized("正文规则"), present: !source.ruleContent.content.isEmpty)
                } header: {
                    Text(localized("规则"))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .interfaceSectionSurface()

                if !source.bookSourceComment.isEmpty {
                    Section {
                        Text(source.bookSourceComment)
                            .font(DSFont.subheadline)
                            .foregroundColor(DSColor.textSecondary)
                            .textSelection(.enabled)
                    } header: {
                        Text(localized("注释"))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .interfaceSectionSurface()
                }

                if !source.variableComment.isEmpty {
                    Section {
                        Text(source.variableComment)
                            .font(DSFont.subheadline)
                            .foregroundColor(DSColor.textSecondary)
                            .textSelection(.enabled)
                    } header: {
                        Text(localized("源变量说明"))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .interfaceSectionSurface()
                }
            }
            .softScrollEdges()
            .navigationTitle(localized("查看详情"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(localized("关闭"))
                }
            }
        }
    }

    private var displayName: String {
        source.bookSourceName.isEmpty ? localized("未命名书源") : source.bookSourceName
    }

    private var supportsExplore: Bool {
        source.enabledExplore
            && !source.exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func validationText(_ summary: SourceValidationSummary) -> String {
        let label: String
        switch summary.health {
        case .passed:       label = localized("验证通过")
        case .fetchError:   label = localized("抓取异常")
        case .contentError: label = localized("正文异常")
        }
        return "\(label)・\(summary.responseMs) ms"
    }

    /// Label + value as one VoiceOver element, so a detail row is read as
    /// 「網址，https://…」 instead of two separate swipes.
    private func infoRow(_ label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(label)
                .font(DSFont.caption)
                .foregroundColor(DSColor.textSecondary)
            Text(value)
                .font(monospaced ? DSFont.fixed(size: 13, design: .monospaced) : DSFont.subheadline)
                .foregroundColor(DSColor.textPrimary)
                .textSelection(.enabled)
        }
        .padding(.vertical, DSSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func ruleRow(_ label: String, present: Bool) -> some View {
        HStack {
            Text(label)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textPrimary)
            Spacer()
            Image(systemName: present ? "checkmark.circle.fill" : "minus.circle")
                .foregroundColor(present ? DSColor.success : DSColor.textSecondary.opacity(0.5))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(localized(present ? "已设定" : "未设定"))
    }
}

#Preview {
    var source = BookSource()
    source.bookSourceName = "范例书源"
    source.bookSourceUrl = "https://example.com"
    source.bookSourceGroup = "小说"
    source.searchUrl = "https://example.com/search?q={{key}}"
    source.bookSourceComment = "这是一个范例书源的注释。"
    return BookSourceInfoSheet(
        source: source,
        validation: SourceValidationSummary(health: .passed, responseMs: 320)
    )
}
