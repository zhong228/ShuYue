import Combine
import SwiftUI
import UIKit

/// 設定 → 診斷與回報.
///
/// The device-readable window onto `DiagnosticLog`. Everything the app logs already
/// went to `os_log`, which needs a Mac and Console.app — so in practice a user who
/// hit a bug could only ever report "it did the thing again". This screen turns that
/// into a file they can send.
///
/// Pushed page, so `.inline` title mode (docs/design.md §2.1 — only the tab roots
/// use `rootTabTitle(_:onScroll:)`).
struct DiagnosticsView: View {

    @StateObject private var model = DiagnosticsViewModel()
    @State private var searchText = ""
    @State private var severityFilter: SeverityFilter = .all
    @State private var categoryFilter: DiagnosticCategory?
    @State private var showClearConfirmation = false
    @State private var showCopiedAlert = false
    /// Set by the 匯出目前篩選 menu row before iOS 18, where a `Menu` cannot own a
    /// share sheet. See `MenuShareHandoff`.
    @State private var pendingShare: PendingShareExport<DiagnosticReportBundle>?
    /// Fixed once per visit. `filename()` stamps the current time, so recomputing it
    /// inside `body` would hand SwiftUI a different value on every render and make
    /// the export control point at a different filename after state updates.
    @State private var exportFilename = DiagnosticReportBundle.filename()

    enum SeverityFilter: String, CaseIterable, Identifiable {
        case all
        case noticeAndUp
        case reportableOnly

        var id: String { rawValue }

        var localizedName: String {
            switch self {
            case .all:            return localized("全部")
            case .noticeAndUp:    return localized("提示以上")
            case .reportableOnly: return localized("只看异常")
            }
        }

        var minimum: DiagnosticSeverity {
            switch self {
            case .all:            return .trace
            case .noticeAndUp:    return .notice
            case .reportableOnly: return .anomaly
            }
        }
    }

    // MARK: - Derived

    private var filteredEntries: [DiagnosticEntry] {
        var entries = model.entries.filter { $0.severity >= severityFilter.minimum }
        if let categoryFilter {
            entries = entries.filter { $0.category == categoryFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.message.lowercased().contains(query)
                || ($0.detail?.lowercased().contains(query) ?? false)
        }
    }

    /// Only anomalies the user has not already sent. Exporting or copying the log
    /// acknowledges everything in it, so the banner goes quiet until something new
    /// happens rather than nagging about a report already made.
    private var reportableCount: Int {
        _ = model.acknowledgementRevision
        return model.entries.filter { DiagnosticLog.shared.isUnreported($0) }.count
    }

    /// The whole session. What 匯出並回報 sends, and what silences the banner.
    private var exportBundle: DiagnosticReportBundle {
        DiagnosticReportBundle(
            filename: exportFilename,
            entries: model.entries,
            session: model.session,
            uncleanSessions: model.uncleanSessions
        )
    }

    /// Only what the filters above are showing, for sharing one slice of a session.
    ///
    /// `acknowledgesReport: false` — a subset must not silence the banner. See the
    /// property's own note in `DiagnosticReportBundle`.
    private var filteredExportBundle: DiagnosticReportBundle {
        DiagnosticReportBundle(
            filename: exportFilename,
            entries: filteredEntries,
            session: model.session,
            uncleanSessions: model.uncleanSessions,
            acknowledgesReport: false
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                exportCard
                if !model.uncleanSessions.isEmpty {
                    crashSessionsCard
                }
                filterCard
                logListCard
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        }
        .softScrollEdges()
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: localized("搜寻纪录")
        )
        .navigationTitle(localized("帮助与诊断"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = exportBundle.render()
                        showCopiedAlert = true
                    } label: {
                        Label(localized("复制全部"), systemImage: "doc.on.doc")
                    }
                    MenuShareRow(
                        label: localized("汇出目前筛选"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        makeExport: {
                            PendingShareExport(
                                title: localized("汇出目前筛选"),
                                name: exportFilename,
                                item: filteredExportBundle
                            )
                        },
                        onHandoff: { pendingShare = $0 }
                    )
                    Button {
                        model.reload()
                    } label: {
                        Label(localized("重新整理"), systemImage: "arrow.clockwise")
                    }
                    #if DEBUG
                    Button {
                        MetricKitDiagnosticReporter.shared.injectSampleDiagnosticForTesting()
                        ChapterRetryLog.resetForTesting()
                        ChapterRetryLog.record(.fetchCancelled, chapter: 42, bookId: "sample")
                        ChapterRetryLog.record(.fetchCancelled, chapter: 42, bookId: "sample")
                        ChapterRetryLog.record(.cacheInconsistent, chapter: 42, bookId: "sample")
                        model.reload()
                    } label: {
                        Label("Inject sample anomaly", systemImage: "ladybug")
                    }
                    #endif
                    Divider()
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label(localized("清除纪录"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(localized("更多动作"))
            }
        }
        .confirmationDialog(
            localized("清除所有诊断纪录？"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("清除"), role: .destructive) { model.clear() }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("清除后无法复原。如果要回报问题，请先汇出。"))
        }
        .sheet(item: $pendingShare) { ShareExportSheet(export: $0) }
        .alert(localized("已复制"), isPresented: $showCopiedAlert) {
            Button(localized("好"), role: .cancel) {}
        } message: {
            Text(localized("诊断纪录已复制到剪贴簿。"))
        }
        .task { model.loadIfNeeded() }
    }

    // MARK: - Cards

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            if reportableCount > 0 {
                DiagnosticAnomalyBanner(count: reportableCount)
                    .padding(.horizontal, DSSpacing.sm)
            }
            ShareLink(item: exportBundle, preview: SharePreview(exportBundle.filename)) {
                Label(
                    reportableCount > 0 ? localized("汇出并回报") : localized("汇出纪录"),
                    systemImage: "square.and.arrow.up"
                )
                .font(DSFont.subheadline.weight(.medium))
                .foregroundStyle(DSColor.textOnAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                .background(DSColor.appAccent)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, reportableCount > 0 ? 0 : DSSpacing.sm)
            Text(localized("包含这次启动的完整纪录，不受下方筛选影响。"))
                .font(DSFont.caption2)
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.md)
                .padding(.bottom, DSSpacing.sm)
        }
        .padding(.vertical, DSSpacing.sm)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var crashSessionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localized("上次未正常结束"))
                .font(DSFont.footnote.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.xs)
            ForEach(model.uncleanSessions) { session in
                DiagnosticCrashSessionRow(session: session)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                if session.id != model.uncleanSessions.last?.id {
                    cardDivider
                }
            }
            Text(localized("App 在使用中结束，不是被系统回收。详细内容下次启动后才会送达。"))
                .font(DSFont.caption2)
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.md)
                .padding(.bottom, DSSpacing.sm)
        }
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(localized("筛选"))
                .font(DSFont.footnote.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.xs)

            severityStrip

            cardDivider

            HStack {
                Text(localized("分类"))
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                Picker(localized("分类"), selection: $categoryFilter) {
                    Text(localized("全部")).tag(DiagnosticCategory?.none)
                    ForEach(DiagnosticCategory.allCases, id: \.self) { category in
                        Text(category.localizedName).tag(DiagnosticCategory?.some(category))
                    }
                }
                .pickerStyle(.menu)
                .tint(DSColor.appAccent)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)

            cardDivider

            Toggle(localized("记录详细追踪"), isOn: $model.isVerboseEnabled)
                .tint(DSColor.appAccent)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)

            Text(localized("记下每一次翻页与解析步骤。关闭时仍会记录错误。"))
                .font(DSFont.caption2)
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.md)
                .padding(.bottom, DSSpacing.sm)
        }
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var severityStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(SeverityFilter.allCases) { filter in
                    let selected = severityFilter == filter
                    Button {
                        withAnimation(DSAnimation.standard) {
                            severityFilter = filter
                        }
                    } label: {
                        Text(filter.localizedName)
                            .font(DSFont.fixed(size: 13, weight: .medium))
                            .foregroundColor(selected ? DSColor.textOnAccent : DSColor.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selected ? DSColor.appAccent : DSColor.neutralControlFill)
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private var logListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localized("纪录"))
                .font(DSFont.footnote.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.xs)

            if model.isLoading {
                HStack(spacing: DSSpacing.md) {
                    ProgressView()
                    Text(localized("载入中…"))
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
            } else if filteredEntries.isEmpty {
                emptyState
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
            } else {
                ForEach(filteredEntries) { entry in
                    DiagnosticEntryRow(entry: entry)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, DSSpacing.sm)
                    if entry.id != filteredEntries.last?.id {
                        cardDivider
                    }
                }
            }
        }
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            UnavailableLabel(localized("没有符合的纪录"), systemImage: "text.magnifyingglass")
        } description: {
            Text(model.entries.isEmpty
                 ? localized("目前没有任何诊断纪录。继续使用 app，有状况时就会出现在这里。")
                 : localized("换一个筛选条件或搜寻字词试试。")).foregroundStyle(DSColor.textSecondary)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            .fill(DSColor.surface)
            .shadow(color: DSColor.shadow, radius: 3, x: 0, y: 1)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            .stroke(DSColor.separator.opacity(0.5), lineWidth: 0.5)
    }

    private var cardDivider: some View {
        Divider()
            .padding(.leading, DSSpacing.md)
    }
}

/// Owns loading snapshots off the main thread.
///
/// `DiagnosticLog.snapshot()` decodes the whole on-disk log, so it must not run on
/// the main actor. Separating it into a view model also keeps `@Published` writes out
/// of view-update time — this codebase has already paid for that mistake once
/// ("Publishing changes from within view updates", see the visible-refresh ack).
@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published private(set) var entries: [DiagnosticEntry] = []
    @Published private(set) var uncleanSessions: [DiagnosticSession] = []
    @Published private(set) var isLoading = false
    /// Bumped when the log is exported or copied. Nothing reads the value — publishing
    /// it is what makes `reportableCount` recompute against the new watermark.
    @Published private(set) var acknowledgementRevision = 0

    private var acknowledgementObserver: NSObjectProtocol?

    @Published var isVerboseEnabled: Bool {
        didSet {
            guard isVerboseEnabled != oldValue else { return }
            DiagnosticLog.shared.isVerboseEnabled = isVerboseEnabled
        }
    }

    let session = DiagnosticLog.shared.currentSession

    private var hasLoaded = false

    init() {
        isVerboseEnabled = DiagnosticLog.shared.isVerboseEnabled
        acknowledgementObserver = NotificationCenter.default.addObserver(
            forName: DiagnosticLog.didAcknowledgeReported,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.acknowledgementRevision += 1 }
        }
    }

    deinit {
        if let acknowledgementObserver {
            NotificationCenter.default.removeObserver(acknowledgementObserver)
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        reload()
    }

    func reload() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let log = DiagnosticLog.shared
            let entries = log.snapshot()
            let unclean = log.uncleanPreviousSessions()
            await MainActor.run { [weak self] in
                self?.entries = entries
                self?.uncleanSessions = unclean
                self?.isLoading = false
            }
        }
    }

    func clear() {
        DiagnosticLog.shared.clear()
        entries = []
        uncleanSessions = []
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
    }
}
