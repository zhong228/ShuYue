import SwiftUI
import UniformTypeIdentifiers

private enum ReplaceRulePresentationRoute: Hashable {
    case add
    case importFile
}

// MARK: - List View

/// Manage user-configurable global replace rules.
/// Presented from Settings / Profile.
struct ReplaceRuleListView: View {

    @ObservedObject private var store = ReplaceRuleStore.shared
    @ObservedObject private var gs = GlobalSettings.shared
    @State private var showingAdd = false
    @State private var showingImportFile = false
    @State private var showLegacyActionChooser = false
    @State private var legacyActionSequence =
        DismissalSequencedPresentation<ReplaceRulePresentationRoute>()
    @State private var editingRule: ReplaceRule?
    @State private var importAlert: ReplaceRuleImportAlert?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // 分组卡片：规则列表合成一张卡片，替代系统 List（2026-10-25）。卡片里没有
            // swipeActions，编辑与删除改由行内长按菜单提供。
            ScrollView {
                AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
                VStack(spacing: DSSpacing.lg) {
                    if store.rules.isEmpty {
                        VStack(spacing: DSSpacing.lg) {
                            Image(systemName: "text.magnifyingglass")
                                .font(DSFont.fixed(size: 48))
                                .foregroundStyle(DSColor.textSecondary)
                            Text(localized("尚无替换规则"))
                                .foregroundStyle(DSColor.textSecondary)
                            Button(localized("新增规则")) { showingAdd = true }
                                .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DSSpacing.xxl)
                    } else {
                        DSSettingsGroupCard(title: "") {
                            ForEach(store.rules) { rule in
                                ReplaceRuleRow(rule: rule) {
                                    editingRule = rule
                                }
                                .contextMenu {
                                    Button {
                                        editingRule = rule
                                    } label: {
                                        Label(localized("编辑"), systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        store.delete(id: rule.id)
                                    } label: {
                                        Label(localized("删除"), systemImage: "trash")
                                    }
                                }
                                .dsSettingsCardRow(minHeight: 0)
                                .padding(.vertical, DSSpacing.xs)

                                if rule.id != store.rules.last?.id {
                                    DSSettingsCardDivider()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.xxl * 2)
            }
            }
            .softScrollEdges()
            .navigationTitle(localized("文字修正"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    addOrImportToolbarControl
                    .accessibilityLabel(localized("新增或汇入"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .sheet(
                isPresented: $showLegacyActionChooser,
                onDismiss: presentLegacyActionAfterChooserDismissal
            ) {
                AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
                    DismissalSequencedActionChooser(
                        title: localized("新增或汇入"),
                        actions: [
                            DismissalSequencedAction(
                                route: .add,
                                title: localized("新增规则"),
                                systemImage: "plus"
                            ),
                            DismissalSequencedAction(
                                route: .importFile,
                                title: localized("汇入替换规则 JSON"),
                                systemImage: "square.and.arrow.down"
                            ),
                        ],
                        onSelect: { legacyActionSequence.select($0) }
                    )
                }
            }
            .sheet(isPresented: $showingAdd) {
                ReplaceRuleEditView(rule: nil) { store.add($0) }
            }
            .sheet(item: $editingRule) { rule in
                ReplaceRuleEditView(rule: rule) { store.update($0) }
            }
            .fileImporter(
                isPresented: $showingImportFile,
                allowedContentTypes: [UTType.json, UTType.plainText]
            ) { result in
                handleImport(result)
            }
            .alert(item: $importAlert) { alert in
                Alert(
                    title: Text(localized(alert.title)),
                    message: Text(alert.message),
                    dismissButton: .default(Text(localized("完成")))
                )
            }
        }
    }

    @ViewBuilder
    private var addOrImportToolbarControl: some View {
        if MenuModalPresentationPolicy.requiresDismissalSequencedChooser {
            Button {
                legacyActionSequence.cancel()
                showLegacyActionChooser = true
            } label: {
                Image(systemName: "plus")
            }
        } else {
            Menu {
                Button {
                    showingAdd = true
                } label: {
                    Label(localized("新增规则"), systemImage: "plus")
                }

                Button {
                    showingImportFile = true
                } label: {
                    Label(
                        localized("汇入替换规则 JSON"),
                        systemImage: "square.and.arrow.down"
                    )
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private func presentLegacyActionAfterChooserDismissal() {
        guard let route = legacyActionSequence.consumeAfterDismissal() else {
            return
        }
        switch route {
        case .add:
            showingAdd = true
        case .importFile:
            showingImportFile = true
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let count = try store.importFromLegadoData(data)
                importAlert = ReplaceRuleImportAlert(
                    title: "成功汇入",
                    message: String(format: localized("已汇入 %d 条替换规则"), count)
                )
            } catch {
                importAlert = ReplaceRuleImportAlert(
                    title: "汇入失败",
                    message: String(format: localized("替换规则汇入失败：%@"), error.localizedDescription)
                )
            }
        case .failure(let error):
            importAlert = ReplaceRuleImportAlert(
                title: "汇入失败",
                message: error.localizedDescription
            )
        }
    }
}

private struct ReplaceRuleImportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Row

private struct ReplaceRuleRow: View {

    let rule: ReplaceRule
    let onTap: () -> Void
    @ObservedObject private var store = ReplaceRuleStore.shared
    @ObservedObject private var gs = GlobalSettings.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.name.isEmpty ? localized("未命名规则") : rule.name)
                        .font(DSFont.subheadline)
                        .bold()
                        .foregroundColor(rule.enabled ? .primary : .secondary)

                    if rule.scope != "global" {
                        Text(localized("书源"))
                            .font(DSFont.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DSColor.highlight)
                            .foregroundColor(DSColor.accent)
                            .cornerRadius(3)
                    }
                    if rule.isRegex {
                        Text("Regex")
                            .font(DSFont.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.12))
                            .foregroundColor(.purple)
                            .cornerRadius(3)
                    }
                }
                Text(rule.pattern)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                if !rule.replacement.isEmpty {
                    Text("→ \(rule.replacement)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { var r = rule; r.enabled = $0; store.update(r) }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Edit View

struct ReplaceRuleEditView: View {

    @State private var rule: ReplaceRule
    let onSave: (ReplaceRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var gs = GlobalSettings.shared

    init(rule: ReplaceRule?, onSave: @escaping (ReplaceRule) -> Void) {
        _rule = State(initialValue: rule ?? ReplaceRule(name: "", pattern: ""))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            // 分组卡片：基本 / 匹配 / 作用範圍 三张卡片，替代系统 Form Section（2026-10-25）。
            ScrollView {
                AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
                VStack(spacing: DSSpacing.lg) {
                    DSSettingsGroupCard(title: localized("基本")) {
                        TextField(localized("规则名称"), text: $rule.name)
                            .dsSettingsCardRow()

                        DSSettingsCardDivider()

                        DSSettingsCardToggle(
                            title: localized("启用"),
                            systemImage: "checkmark.circle",
                            isOn: $rule.enabled
                        )
                    }

                    DSSettingsGroupCard(title: localized("匹配")) {
                        DSSettingsCardToggle(
                            title: localized("正则表达式"),
                            systemImage: "asterisk",
                            isOn: $rule.isRegex
                        )

                        DSSettingsCardDivider()

                        TextField(localized("匹配模式"), text: $rule.pattern)
                            .font(DSFont.fixed(size: 14, design: .monospaced))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .dsSettingsCardRow()

                        DSSettingsCardDivider()

                        TextField(localized("替换为（空白=删除）"), text: $rule.replacement)
                            .font(DSFont.fixed(size: 14, design: .monospaced))
                            .autocapitalization(.none)
                            .dsSettingsCardRow()
                    }

                    DSSettingsGroupCard(title: localized("作用范围")) {
                        Picker(localized("范围"), selection: $rule.scope) {
                            Text(localized("全局")).tag("global")
                            if rule.scope != "global" {
                                Text(rule.scope).tag(rule.scope)
                            }
                        }
                        .pickerStyle(.inline)
                        .dsSettingsCardRow(minHeight: 0)
                        .padding(.vertical, DSSpacing.xs)
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.xxl * 2)
            }
            }
            .softScrollEdges()
            .navigationTitle(rule.name.isEmpty ? localized("新增规则") : rule.name)
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave(rule)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(rule.pattern.isEmpty)
                }
            }
        }
    }
}
