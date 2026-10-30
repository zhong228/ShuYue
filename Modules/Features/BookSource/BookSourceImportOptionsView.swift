import SwiftUI

// MARK: - BookSourceImportOptionsSection

/// The 匯入選項 row inside the book-source import confirmation list, with a one-line summary
/// of what is currently set. Pushes the full options page.
struct BookSourceImportOptionsSection: View {
    @Binding var options: BookSourceImportOptions
    let groupCandidates: [BookSourceGroupCandidate]

    var body: some View {
        Section {
            NavigationLink {
                BookSourceImportOptionsView(
                    options: $options,
                    groupCandidates: groupCandidates
                )
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    Label(localized("汇入选项"), systemImage: "slider.horizontal.3")
                        .foregroundColor(DSColor.textPrimary)
                    Spacer(minLength: DSSpacing.sm)
                    Text(summary)
                        .font(DSFont.subheadline)
                        .foregroundColor(DSColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minHeight: DSLayout.minimumTapTarget)
            }
            .accessibilityLabel(localized("汇入选项"))
            .accessibilityValue(summary)
        }
        .interfaceSectionSurface()
    }

    /// What is switched on, so the user doesn't have to open the page to check.
    private var summary: String {
        var parts: [String] = []
        if options.keepName { parts.append(localized("保留原名")) }
        if options.keepGroup { parts.append(localized("保留分组")) }
        if options.keepEnable { parts.append(localized("保留启用状态")) }
        if let group = options.trimmedGroupName {
            parts.append(
                String(
                    format: localized(options.addsToExistingGroups ? "附加分组「%@」" : "分组「%@」"),
                    group
                )
            )
        }
        return parts.isEmpty ? localized("预设") : parts.joined(separator: " · ")
    }
}

// MARK: - BookSourceImportOptionsView

/// 匯入選項: what an import keeps from the local copy when it overwrites a source the library
/// already has, and which group the imported sources land in — Legado's import-dialog menu,
/// as a page.
struct BookSourceImportOptionsView: View {
    @Binding var options: BookSourceImportOptions
    let groupCandidates: [BookSourceGroupCandidate]

    @State private var showsGroupPicker = false

    var body: some View {
        List {
            Section {
                Toggle(localized("保留原名"), isOn: $options.keepName)
                Toggle(localized("保留分组"), isOn: $options.keepGroup)
                Toggle(localized("保留启用状态"), isOn: $options.keepEnable)
            } header: {
                Text(localized("覆盖已有书源时"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("书源包会带著作者自己的名称、分组与启用状态。开启后，这几项沿用本机的设定，只更新规则。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            Section {
                Button {
                    showsGroupPicker = true
                } label: {
                    HStack(spacing: DSSpacing.sm) {
                        Text(localized("汇入到分组"))
                            .foregroundColor(DSColor.textPrimary)
                        Spacer(minLength: DSSpacing.sm)
                        Text(options.trimmedGroupName ?? localized("不指定"))
                            .foregroundColor(DSColor.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(minHeight: DSLayout.minimumTapTarget)
                }
                .accessibilityLabel(localized("汇入到分组"))
                .accessibilityValue(options.trimmedGroupName ?? localized("不指定"))

                if options.trimmedGroupName != nil {
                    Picker(localized("分组方式"), selection: $options.addsToExistingGroups) {
                        Text(localized("取代原分组")).tag(false)
                        Text(localized("附加到原分组")).tag(true)
                    }
                    Button(role: .destructive) {
                        options.groupName = nil
                        options.addsToExistingGroups = false
                    } label: {
                        Text(localized("清除分组指定"))
                    }
                    .frame(minHeight: DSLayout.minimumTapTarget)
                }
            } header: {
                Text(localized("分组"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                if options.trimmedGroupName != nil, options.keepGroup {
                    Text(localized("已开启「保留分组」：本机已有的书源会先还原成原本的分组，再套用这里的指定。"))
                        .dsSectionFooter()
                }
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(localized("汇入选项"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .sheet(isPresented: $showsGroupPicker) {
            BookSourceGroupPickerSheet(
                title: localized("汇入到分组"),
                subtitle: localized("选中的书源会归到这个分组"),
                candidates: groupCandidates,
                excluded: "",
                defaultGroupTitle: nil,
                defaultGroupName: "",
                allowsNewGroup: true,
                onSelect: { name in
                    options.groupName = name
                }
            )
        }
    }
}

#Preview {
    NavigationStack {
        BookSourceImportOptionsView(
            options: .constant(.manualDefaults),
            groupCandidates: [
                BookSourceGroupCandidate(name: "玄幻", count: 42),
                BookSourceGroupCandidate(name: "都市", count: 17),
            ]
        )
    }
}
