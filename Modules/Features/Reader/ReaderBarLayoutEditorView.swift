import SwiftUI
import UIKit

/// 頁首頁尾 editor: which info field sits in which of the six bar slots, how the
/// two bars are drawn, and shared style with individual field colors.
///
/// A pushed settings page rather than the in-place drag canvas it replaces. Two
/// things fall out of that: it works in scroll mode (the canvas was paged-only,
/// which is why scroll mode had no bars at all), and it never presents a sheet
/// from inside a sheet — the iOS 17 trap `Technotes/iOS17MenuModalPresentation.md`
/// documents.
struct ReaderBarLayoutEditorView: View {
    @ObservedObject private var settings = GlobalSettings.shared
    @StateObject private var readerConfig = ReaderConfig.shared
    @StateObject private var clock = ClockBatteryModel()
    /// The preview is drawn by the same renderer the reading page bakes in, so
    /// what you set here is literally what the page draws.
    @State private var barBuilder = ReaderBarRenderModelBuilder()

    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .callout) private var previewHeight = 132.0

    let theme: ReaderTheme
    var readerSafeTop: CGFloat = 0
    var readerSafeBottom: CGFloat = 0
    var svgAssetStore: ReaderOverlaySVGAssetStore?

    @State private var saveFailed = false
    @State private var editsChapterOpening = false

    // MARK: - Body

    var body: some View {
        List {
            previewSection
            Section {
                Picker(localized("页面类型"), selection: $editsChapterOpening) {
                    Text(localized("正文")).tag(false)
                    Text(localized("章节首页")).tag(true)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(localized("两种页面可选不同组件，边距与共用样式一致。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
            barSection(.header)
            barSection(.footer)
            styleSection
        }
        .softScrollEdges()
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DSColor.groupedBackground)
        .navigationTitle(localized("页首页尾"))
        .toolbarTitleDisplayMode(.inline)
        .alert(localized("无法储存页首页尾设定"), isPresented: $saveFailed) {
            Button(localized("确定"), role: .cancel) {}
        } message: {
            Text(localized("请稍后再试。"))
        }
    }

    // MARK: - Preview

    /// Shows both bars over the reader's own background, with the real clock and
    /// battery. Sample values stand in for the book and chapter, which the editor
    /// has no access to when it is reached from Settings rather than the reader.
    private var previewSection: some View {
        Section {
            ZStack {
                Color(uiColor: theme.uiBackgroundColor)
                VStack(spacing: 0) {
                    if visibility.showsHeader {
                        bar(.header)
                    }
                    Spacer(minLength: DSSpacing.sm)
                    Text(localized("正文预览"))
                        .font(DSFont.callout)
                        .foregroundStyle(Color(uiColor: theme.uiTextColor))
                    Spacer(minLength: DSSpacing.sm)
                    if visibility.showsFooter {
                        bar(.footer)
                    }
                }
                .padding(.vertical, DSSpacing.sm)
            }
            .frame(height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
            .listRowInsets(EdgeInsets())
            .accessibilityElement(children: .contain)
        } footer: {
            Text(localized("预览使用示例书名与章节名，时间与电量为实际数值。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private func bar(_ which: ReaderBar) -> some View {
        ReaderBarView(
            model: barBuilder.model(
                for: which,
                layout: settings.readerBarLayout,
                content: previewContent,
                readerTextColor: theme.uiTextColor,
                horizontalPadding: which == .header
                    ? readerConfig.readerHeaderHorizontalPadding
                    : readerConfig.readerFooterHorizontalPadding,
                svgAssetStore: svgAssetStore,
                userInterfaceStyle: theme == .night ? .dark : .light,
                displayScale: displayScale
            )
        )
    }

    // MARK: - Fields

    private func slotSummary(_ slot: ReaderBarSlot) -> String {
        let titles = layout.fields(in: slot).map { localized(ReaderBarFieldNaming.titleKey(for: $0.kind)) }
        return titles.isEmpty ? localized("隐藏") : titles.joined(separator: localized("、"))
    }

    private func slotEditor(_ slot: ReaderBarSlot) -> some View {
        List {
            Section {
                ForEach(ReaderOverlayComponentKind.allCases, id: \.self) { kind in
                    Toggle(localized(ReaderBarFieldNaming.titleKey(for: kind)), isOn: Binding(
                        get: { field(kind, in: slot) != nil },
                        set: { selected in update { $0.setSelected(selected, kind: kind, in: slot) } }
                    ))
                }
            } header: {
                Text(localized("显示组件"))
                    .foregroundStyle(DSColor.textSecondary)
            }
            .interfaceSectionSurface()

            ForEach(layout.fields(in: slot)) { selected in
                Section {
                    Toggle(localized("自订"), isOn: Binding(
                        get: { field(selected.kind, in: slot)?.isCustomizing ?? false },
                        set: { value in updateField(selected.kind, in: slot) { $0.usesCustomOptions = value } }
                    ))
                    if selected.isCustomizing {
                        fieldOptions(selected.kind, in: slot)
                        fieldColorOptions(selected.kind, in: slot)
                    }
                } header: {
                    Text(localized(ReaderBarFieldNaming.titleKey(for: selected.kind)))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .interfaceSectionSurface()
            }
        }
        .softScrollEdges()
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DSColor.groupedBackground)
        .navigationTitle(localized(slot.titleKey))
        .toolbarTitleDisplayMode(.inline)
    }

    private func field(_ kind: ReaderOverlayComponentKind, in slot: ReaderBarSlot) -> ReaderBarField? {
        layout.fields.first { $0.kind == kind && $0.slot == slot }
    }

    private func updateField(_ kind: ReaderOverlayComponentKind, in slot: ReaderBarSlot,
                             _ mutate: (inout ReaderBarField) -> Void) {
        update { layout in
            guard let index = layout.fields.firstIndex(where: { $0.kind == kind && $0.slot == slot }) else { return }
            mutate(&layout.fields[index])
        }
    }

    private func fieldColorOptions(_ kind: ReaderOverlayComponentKind, in slot: ReaderBarSlot) -> some View {
        let title = String(format: localized("%@颜色"), localized(ReaderBarFieldNaming.titleKey(for: kind)))
        return DisclosureGroup {
            Picker(localized("颜色"), selection: Binding<ReaderOverlayColorSource?>(
                get: { field(kind, in: slot)?.color?.source },
                set: { source in
                    updateField(kind, in: slot) { field in
                        var color = field.color ?? ReaderOverlayColorReference(source: .custom)
                        if let source { color.source = source }
                        field.color = source == nil ? nil : color
                    }
                }
            )) {
                Text(localized("沿用共用颜色")).tag(Optional<ReaderOverlayColorSource>.none)
                Text(localized("跟随正文颜色")).tag(Optional(ReaderOverlayColorSource.readerText))
                Text(localized("自订颜色")).tag(Optional(ReaderOverlayColorSource.custom))
            }
            .pickerStyle(.menu)
            .accessibilityLabel(title)

            if field(kind, in: slot)?.color?.source == .custom {
                ColorPicker(localized("亮色模式"), selection: colorBinding(dark: false, field: kind, slot: slot))
                    .accessibilityLabel("\(title)，\(localized("亮色模式"))")
                ColorPicker(localized("深色模式"), selection: colorBinding(dark: true, field: kind, slot: slot))
                    .accessibilityLabel("\(title)，\(localized("深色模式"))")
            }
        } label: {
            Text(title)
                .foregroundStyle(DSColor.textPrimary)
        }
        .font(DSFont.body)
    }

    @ViewBuilder
    private func fieldOptions(_ kind: ReaderOverlayComponentKind, in slot: ReaderBarSlot) -> some View {
        let configuration = field(kind, in: slot)?.configuration
            ?? ReaderOverlayComponentConfiguration()

        switch kind {
        case .battery:
            Toggle(
                localized("显示电量百分比"),
                isOn: Binding(
                    get: { configuration.showsBatteryPercentage },
                    set: { newValue in
                        var next = configuration
                        next.showsBatteryPercentage = newValue
                        updateField(kind, in: slot) { $0.configuration = next }
                    }
                )
            )
            .font(DSFont.body)

        case .customText:
            TextField(
                localized("自订文字"),
                text: Binding(
                    get: { configuration.customText },
                    set: { newValue in
                        var next = configuration
                        next.customText = newValue
                        updateField(kind, in: slot) { $0.configuration = next }
                    }
                )
            )
            .font(DSFont.body)

        case .currentTime, .currentDate, .chapterPage, .readingDuration, .remainingTime:
            Picker(
                selection: Binding(
                    get: { configuration.displayFormat },
                    set: { newValue in
                        var next = configuration
                        next.displayFormat = newValue
                        updateField(kind, in: slot) { $0.configuration = next }
                    }
                )
            ) {
                ForEach(ReaderBarFieldNaming.formats(for: kind), id: \.self) { format in
                    Text(localized(ReaderBarFieldNaming.titleKey(for: format))).tag(format)
                }
            } label: {
                Text(localized("显示格式"))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .pickerStyle(.menu)

        default:
            EmptyView()
        }
    }

    // MARK: - Per-bar

    private func barSection(_ which: ReaderBar) -> some View {
        Section {
            Toggle(
                localized(which == .header ? "显示页眉" : "显示页脚"),
                isOn: which == .header
                    ? $readerConfig.readerHeaderVisible
                    : $readerConfig.readerFooterVisible
            )
            .font(DSFont.body)

            Toggle(
                localized("分隔线"),
                isOn: Binding(
                    get: {
                        which == .header ? layout.showsHeaderDivider : layout.showsFooterDivider
                    },
                    set: { newValue in
                        update {
                            if which == .header {
                                $0.showsHeaderDivider = newValue
                            } else {
                                $0.showsFooterDivider = newValue
                            }
                        }
                    }
                )
            )
            .font(DSFont.body)

            ForEach(ReaderBarSlot.slots(in: which)) { slot in
                NavigationLink {
                    slotEditor(slot)
                } label: {
                    ThemedLabeledContent(localized(slot.titleKey), value: slotSummary(slot))
                }
            }

            BarSliderRow(
                title: localized("上边距"),
                value: which == .header ? edgeDistanceBinding(for: which) : innerMarginBinding(for: which),
                range: 0...200
            )
            BarSliderRow(
                title: localized("下边距"),
                value: which == .footer ? edgeDistanceBinding(for: which) : innerMarginBinding(for: which),
                range: 0...200
            )
            BarSliderRow(title: localized("左边距"), value: sideMarginBinding(for: which, right: false), range: 0...200)
            BarSliderRow(title: localized("右边距"), value: sideMarginBinding(for: which, right: true), range: 0...200)
        } header: {
            Text(localized(which.titleKey))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("页眉上边距与页脚下边距从画面边缘计算，另一侧控制与正文的间距。"))
                .dsSectionFooter()

        }
        .interfaceSectionSurface()
    }

    // MARK: - Shared style

    private var styleSection: some View {
        Section {
            Toggle(localized("显示组件分隔点"), isOn: Binding(
                get: { layout.showsComponentSeparators },
                set: { value in update { $0.showsComponentSeparators = value } }
            ))
            Picker(localized("颜色"), selection: Binding(
                get: { layout.style.color.source },
                set: { source in update { $0.style.color.source = source } }
            )) {
                Text(localized("跟随正文颜色")).tag(ReaderOverlayColorSource.readerText)
                Text(localized("自订颜色")).tag(ReaderOverlayColorSource.custom)
            }
            .font(DSFont.body)
            .pickerStyle(.menu)

            if layout.style.color.source == .custom {
                ColorPicker(localized("亮色模式"), selection: colorBinding(dark: false))
                    .font(DSFont.body)
                ColorPicker(localized("深色模式"), selection: colorBinding(dark: true))
                    .font(DSFont.body)
            }

            BarSliderRow(
                title: localized("字级"),
                value: Binding(
                    get: { CGFloat(layout.style.fontSize) },
                    set: { newValue in
                        update { $0.style.fontSize = Double(newValue) }
                    }
                ),
                range: Self.fontSizeRange
            )

            Picker(
                selection: Binding(
                    get: { layout.style.weight },
                    set: { newValue in update { $0.style.weight = newValue } }
                )
            ) {
                ForEach(ReaderBarFieldNaming.weights, id: \.self) { weight in
                    Text(localized(ReaderBarFieldNaming.titleKey(for: weight))).tag(weight)
                }
            } label: {
                Text(localized("字重"))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
            }
            .pickerStyle(.menu)

            BarSliderRow(
                title: localized("不透明度"),
                value: Binding(
                    get: { CGFloat(layout.style.opacity) },
                    set: { newValue in update { $0.style.opacity = Double(newValue) } }
                ),
                range: Self.opacityRange,
                step: 0.05,
                valueText: "\(Int((layout.style.opacity * 100).rounded()))%"
            )
        } header: {
            Text(localized("样式"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("此处设定共用样式；各位置选中的组件可开启自订选项。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    // MARK: - State

    private func innerMarginBinding(for bar: ReaderBar) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(bar == .header ? layout.headerMargins.inner : layout.footerMargins.inner) },
            set: { value in update {
                if bar == .header { $0.headerMargins.inner = Double(value) }
                else { $0.footerMargins.inner = Double(value) }
            } }
        )
    }

    private func sideMarginBinding(for bar: ReaderBar, right: Bool) -> Binding<CGFloat> {
        Binding(
            get: {
                let margins = bar == .header ? layout.headerMargins : layout.footerMargins
                let legacy = bar == .header ? readerConfig.readerHeaderHorizontalPadding : readerConfig.readerFooterHorizontalPadding
                return (right ? margins.right : margins.left).map { CGFloat($0) } ?? legacy
            },
            set: { value in update {
                if bar == .header {
                    if right { $0.headerMargins.right = Double(value) } else { $0.headerMargins.left = Double(value) }
                } else {
                    if right { $0.footerMargins.right = Double(value) } else { $0.footerMargins.left = Double(value) }
                }
            } }
        )
    }

    private func edgeDistance(for bar: ReaderBar) -> CGFloat {
        if bar == .header {
            return ReaderLayoutMetrics.headerBarTopOffset(
                safeTop: readerSafeTop,
                headerTopPadding: readerConfig.readerHeaderTopPadding,
                edgeDistance: layout.edgeDistances.header
            )
        }
        return ReaderLayoutMetrics.footerBarBottomOffset(
            safeBottom: readerSafeBottom,
            footerBottomPadding: readerConfig.footerBottomPadding,
            edgeDistance: layout.edgeDistances.footer
        )
    }

    private func edgeDistanceBinding(for bar: ReaderBar) -> Binding<CGFloat> {
        Binding(
            get: { edgeDistance(for: bar) },
            set: { distance in update { $0.edgeDistances[bar] = Double(distance) } }
        )
    }

    private func colorBinding(dark: Bool, field: ReaderOverlayComponentKind? = nil, slot: ReaderBarSlot? = nil) -> Binding<Color> {
        let appearance: UIUserInterfaceStyle = dark ? .dark : .light
        let previewTheme: ReaderTheme = dark ? .night : (theme == .night ? .white : theme)
        return Binding(
            get: {
                var style = layout.style
                if let field {
                    style.color = layout.fields.first { $0.kind == field && $0.slot == slot }?.color ?? style.color
                }
                return Color(uiColor: ReaderBarStyleResolver.resolve(
                    style,
                    readerTextColor: previewTheme.uiTextColor,
                    userInterfaceStyle: appearance
                ).color)
            },
            set: { color in
                guard let hex = ReaderOverlayPresentationResolver.rgbaHex(
                    UIColor(color), userInterfaceStyle: appearance
                ), let value = UInt32(hex.dropFirst(), radix: 16) else { return }
                update { layout in
                    var reference = field.flatMap { kind in
                        layout.fields.first { $0.kind == kind && $0.slot == slot }?.color
                    } ?? layout.style.color
                    reference.source = .custom
                    if dark {
                        reference.darkHexRGBA = value
                    } else {
                        reference.hexRGBA = value
                    }
                    if let field {
                        if let index = layout.fields.firstIndex(where: { $0.kind == field && $0.slot == slot }) {
                            layout.fields[index].color = reference
                        }
                    } else {
                        layout.style.color = reference
                    }
                }
            }
        )
    }

    /// `ClosedRange` needs both bounds on one line — a `...` at the head of a
    /// continuation line parses as a prefix operator, not a range.
    private static let fontSizeRange: ClosedRange<CGFloat> =
        CGFloat(ReaderBarStyle.fontSizeRange.lowerBound)...CGFloat(ReaderBarStyle.fontSizeRange.upperBound)

    private static let opacityRange: ClosedRange<CGFloat> =
        CGFloat(ReaderBarStyle.opacityRange.lowerBound)...CGFloat(ReaderBarStyle.opacityRange.upperBound)

    private var layout: ReaderBarLayout {
        settings.readerBarLayout.resolved(isChapterOpening: editsChapterOpening)
    }

    private var visibility: ReaderBarVisibility {
        ReaderOverlayPresentationPolicy.visibility(
            layout: layout,
            headerEnabled: readerConfig.readerHeaderVisible,
            footerEnabled: readerConfig.readerFooterVisible,
            isChapterOpeningPage: editsChapterOpening
        )
    }

    private var previewContent: ReaderOverlayContentSnapshot {
        ReaderOverlayContentSnapshot(
            bookTitle: localized("示例书名"),
            chapterTitle: localized("第一章 示例章节"),
            chapterPage: editsChapterOpening ? 1 : 3,
            chapterPageCount: 12,
            totalProgress: 0.4523,
            now: clock.now,
            batteryLevel: clock.batteryLevel,
            isCharging: clock.isCharging,
            readingDuration: 1_500,
            estimatedRemainingTime: 4_200
        )
    }

    /// Every edit goes through here so a failed write surfaces once, in one place,
    /// instead of each control silently keeping a value that was never persisted.
    private func update(_ mutate: (inout ReaderBarLayout) -> Void) {
        var next = layout
        mutate(&next)
        if editsChapterOpening {
            next.chapterOpeningFields = next.fields
            next.fields = settings.readerBarLayout.fields
        }
        guard settings.saveReaderBarLayout(next) else {
            saveFailed = true
            return
        }
    }
}

// MARK: - Slider row

/// A `Slider` has no name of its own and announces a fraction of its range, so it
/// carries the row's title and the value shown beside it — `docs/design.md` §7.1.
private struct BarSliderRow: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var step: CGFloat = 1
    var valueText: String?

    private var displayValue: String {
        valueText ?? String(
            format: localized("ReaderOverlay.Format.Points"),
            Int(value.rounded())
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                Text(displayValue)
                    .font(DSFont.body.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }
            .accessibilityHidden(true)

            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(displayValue)
        }
    }
}

// MARK: - Naming

/// Display names for the field kinds, formats and weights the editor offers.
///
/// Separate from `ReaderOverlayPresentationResolver.accessibilityLabel`, which
/// names the same kinds for VoiceOver: that one is spoken mid-sentence with the
/// value after it, this one is a row title. They happen to agree today; keeping
/// them apart means changing one phrasing cannot silently change the other.
enum ReaderBarFieldNaming {
    static func titleKey(for kind: ReaderOverlayComponentKind) -> String {
        switch kind {
        case .bookTitle: "书名"
        case .chapterTitle: "章节名"
        case .chapterPage: "本章页码"
        case .totalProgressText: "总进度"
        case .progressBar: "进度条"
        case .currentTime: "目前时间"
        case .currentDate: "目前日期"
        case .weekday: "星期"
        case .battery: "电量"
        case .readingDuration: "本次阅读时长"
        case .remainingTime: "预估剩余时间"
        case .customText: "自订文字"
        }
    }

    static func titleKey(for format: ReaderOverlayDisplayFormat) -> String {
        switch format {
        case .automatic: "自动"
        case .compact: "精简"
        case .detailed: "详细"
        case .fraction: "分数"
        case .percentage: "百分比"
        case .hourMinute24: "24 小时制"
        case .hourMinute12: "12 小时制"
        }
    }

    static func titleKey(for weight: ReaderOverlayFontWeight) -> String {
        switch weight {
        case .light: "细"
        case .regular: "标准"
        case .medium: "中等"
        case .semibold: "半粗"
        case .bold: "粗"
        }
    }

    static let weights: [ReaderOverlayFontWeight] = [.light, .regular, .medium, .semibold, .bold]

    /// Only the formats a kind actually understands. Offering every case would let
    /// someone set 「24 小時制」 on the page number and see nothing change.
    static func formats(for kind: ReaderOverlayComponentKind) -> [ReaderOverlayDisplayFormat] {
        switch kind {
        case .currentTime: [.automatic, .hourMinute24, .hourMinute12]
        case .chapterPage: [.automatic, .compact, .fraction]
        case .readingDuration, .remainingTime: [.automatic, .compact, .detailed]
        case .currentDate: [.automatic, .compact, .detailed]
        default: [.automatic]
        }
    }
}

#Preview("页首页尾编辑") {
    NavigationStack {
        ReaderBarLayoutEditorView(theme: .sepia)
    }
}

#Preview("页首页尾编辑 · 夜间") {
    NavigationStack {
        ReaderBarLayoutEditorView(theme: .night)
    }
    .preferredColorScheme(.dark)
}
