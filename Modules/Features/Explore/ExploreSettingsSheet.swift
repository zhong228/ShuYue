import SwiftUI

/// 书城设置, behind 探索's gear: how 探索 lays out its entries, how a source's page lays
/// out its categories, and how the charts and shelves fill and load.
struct ExploreSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ExploreSettings.sourcePageLayoutKey)
    private var sourcePageLayout = ExploreSourcePageLayout.default
    @AppStorage(ExploreSettings.rankedKeywordsKey)
    private var rankedKeywordsRaw = ExploreSettings.encodeKeywords(ExploreSettings.defaultRankedKeywords)
    @AppStorage(ExploreSettings.chartBookCountKey)
    private var chartBookCount = ExploreSettings.defaultChartBookCount
    @AppStorage(ExploreSettings.shelfBookCountKey)
    private var shelfBookCount = ExploreSettings.defaultShelfBookCount
    @AppStorage(ExploreSettings.preloadCountKey)
    private var preloadCount = ExploreSettings.defaultPreloadCount
    @AppStorage(BookCoverLoader.downloadLimitKey) private var coverDownloadLimit = 0
    @State private var newKeyword = ""

    private var rankedKeywords: [String] {
        ExploreSettings.decodeKeywords(rankedKeywordsRaw)
    }

    var body: some View {
        NavigationStack {
            Form {
                layoutSection
                // How the charts and shelves fill and load matters only to the magazine
                // layout; the cover limit applies to every cover in the app.
                if sourcePageLayout == .magazine {
                    keywordsSection
                    restoreKeywordsSection
                    bookCountSection
                    preloadSection
                }
                coverSection
            }
            .animation(reduceMotion ? nil : DSAnimation.standard, value: sourcePageLayout)
            .navigationTitle(localized("书城设置"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .explore)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Label(localized("完成"), systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }

    // MARK: Sections

    private var layoutSection: some View {
        Section {
            Picker(selection: $sourcePageLayout) {
                ForEach(ExploreSourcePageLayout.allCases) { layout in
                    Label(localized(layout.titleKey), systemImage: layout.systemImage)
                        .tag(layout)
                }
            } label: {
                SettingsRowLabel(localized("书源页布局"), systemImage: "rectangle.split.2x1")
            }
            .pickerStyle(.menu)
        } header: {
            sectionHeader(localized("布局"))
        } footer: {
            Text(localized("列表是上方一排分类、下方所选分类的书；杂志是每个分类一排书架或一栏榜单。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var keywordsSection: some View {
        Section {
            ForEach(rankedKeywords, id: \.self) { keyword in
                SettingsRowLabel(keyword, systemImage: "number")
            }
            .onDelete { offsets in
                var keywords = rankedKeywords
                keywords.remove(atOffsets: offsets)
                rankedKeywordsRaw = ExploreSettings.encodeKeywords(keywords)
            }
            HStack(spacing: DSSpacing.md) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityHidden(true)
                TextField(localized("新增关键词"), text: $newKeyword)
                    .submitLabel(.done)
                    .onSubmit(addKeyword)
            }
        } header: {
            sectionHeader(localized("竖排榜单关键词"))
        } footer: {
            Text(localized("标题含任一关键词的分类用竖排序号，其余用横滑封面。左滑可删除。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var restoreKeywordsSection: some View {
        Section {
            Button {
                rankedKeywordsRaw = ExploreSettings.encodeKeywords(ExploreSettings.defaultRankedKeywords)
            } label: {
                SettingsRowLabel(
                    localized("恢复预设关键词"),
                    systemImage: "arrow.counterclockwise",
                    role: .action
                )
            }
            .disabled(rankedKeywords == ExploreSettings.defaultRankedKeywords)
        }
        .interfaceSectionSurface()
    }

    private var bookCountSection: some View {
        Section {
            Picker(selection: $chartBookCount) {
                ForEach(ExploreSettings.chartBookCountOptions, id: \.self) { count in
                    Text(count.formatted()).tag(count)
                }
            } label: {
                SettingsRowLabel(localized("竖排展示数"), systemImage: "list.number")
            }
            .pickerStyle(.menu)
            Picker(selection: $shelfBookCount) {
                ForEach(ExploreSettings.shelfBookCountOptions, id: \.self) { count in
                    Text(count == 0 ? localized("全部") : count.formatted()).tag(count)
                }
            } label: {
                SettingsRowLabel(localized("横滑展示数"), systemImage: "rectangle.split.3x1")
            }
            .pickerStyle(.menu)
        } header: {
            sectionHeader(localized("榜单展示数量"))
        }
        .interfaceSectionSurface()
    }

    private var preloadSection: some View {
        Section {
            Picker(selection: $preloadCount) {
                ForEach(ExploreSettings.preloadCountOptions, id: \.self) { count in
                    Text(count.formatted()).tag(count)
                }
            } label: {
                SettingsRowLabel(localized("预加载数量"), systemImage: "arrow.down.circle")
            }
            .pickerStyle(.menu)
        } header: {
            sectionHeader(localized("预加载"))
        } footer: {
            Text(localized("卷到某个分类时，顺便排队载入后面几个分类。数字越大越少看到载入中，但排队的书源请求也越多。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var coverSection: some View {
        Section {
            Picker(selection: $coverDownloadLimit) {
                ForEach(ExploreSettings.coverDownloadLimitOptions, id: \.self) { limit in
                    Text(limit == 0 ? localized("不限制") : limit.formatted()).tag(limit)
                }
            } label: {
                SettingsRowLabel(localized("封面并发数"), systemImage: "arrow.triangle.2.circlepath")
            }
            .pickerStyle(.menu)
        } header: {
            sectionHeader(localized("封面并发"))
        } footer: {
            Text(localized("同时下载的封面上限，书架和书籍详情的封面也算在内。数字越低卷动时越不容易发热，但封面出现得慢一些。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(DSColor.textSecondary)
    }

    private func addKeyword() {
        let keyword = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        newKeyword = ""
        guard !keyword.isEmpty,
              !rankedKeywords.contains(where: { $0.caseInsensitiveCompare(keyword) == .orderedSame })
        else { return }
        rankedKeywordsRaw = ExploreSettings.encodeKeywords(rankedKeywords + [keyword])
    }
}

#Preview {
    ExploreSettingsSheet()
}
