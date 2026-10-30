import SwiftUI

/// 全書與分卷摘要: the book so far, then each read volume.
///
/// Summaries are built from chapter digests of locally available, already-read text only; a
/// run is shown with its call count and confirmed before anything is sent.
struct AIBookSummaryView: View {
    let adapter: AIBookContentAdapter
    @ObservedObject private var service = AIBookSummaryService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var plan: AIBookSummaryPlan?
    @State private var proposal: Proposal?
    @State private var planError: String?
    @State private var confirmClear = false

    private struct Proposal: Identifiable {
        let plan: AIBookSummaryPlan
        let service: AIBookSummaryService.Service
        var id: String { plan.batches.map(\.id).joined() + "\(plan.estimatedCalls)" }
    }

    private var book: UUID { adapter.chunkBookID }
    private var record: AIBookSummaryRecord { service.records[book] ?? AIBookSummaryRecord() }
    private var run: AIBookSummaryService.RunState { service.runs[book] ?? .idle }
    private var isRunning: Bool { if case .running = run { return true } else { return false } }

    var body: some View {
        List {
            bookSection
            actionSection
            if let plan, !plan.readVolumes.isEmpty { volumeSection(plan) }
            if record.book != nil || !record.digests.isEmpty {
                Section {
                    Button(localized("清除本书摘要"), role: .destructive) { confirmClear = true }
                        .disabled(isRunning)
                }
                .interfaceSectionSurface()
            }
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("全书与分卷摘要"))
        .toolbarTitleDisplayMode(.inline)
        .task(id: adapter.contentFingerprint) { await refreshPlan() }
        // A finished or paused run changes what is left to do.
        .onChange(of: service.runs[book]) { _, state in
            if case .running = state { return }
            Task { await refreshPlan() }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { service.pause(book: book) } }
        .onDisappear { service.pause(book: book) }
        .sheet(item: $proposal) { consent($0) }
        .confirmationDialog(localized("清除本书摘要？"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(localized("清除"), role: .destructive) {
                Task {
                    do { try await service.clear(book: book) } catch { planError = error.localizedDescription }
                    await refreshPlan()
                }
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("已整理的逐章、分卷与全书摘要都会删除，重新整理需要再次呼叫模型。"))
        }
    }

    // MARK: - Sections

    @ViewBuilder private var bookSection: some View {
        Section {
            if let summary = record.book {
                AIAnswerMarkdownView(text: summary.text)
                    .padding(.vertical, DSSpacing.xs)
            } else {
                ContentUnavailableView {
                    UnavailableLabel(localized("还没有全书摘要"), systemImage: "text.book.closed")
                } description: {
                    Text(localized("依已读章节逐章整理，再汇整成分卷与全书摘要。")).foregroundStyle(DSColor.textSecondary)
                }
            }
        } header: {
            Text(localized("全书摘要"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            if let summary = record.book {
                Text(String(format: localized("涵盖到第 %d 章"), summary.throughChapter + 1))
                    .dsSectionFooter()
            }
        }
        .interfaceSectionSurface()
    }

    @ViewBuilder private var actionSection: some View {
        Section {
            switch run {
            case let .running(progress):
                ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1))) {
                    Text(String(format: localized("整理中…（%1$d / %2$d）"), progress.completed, progress.total))
                        .foregroundStyle(DSColor.textPrimary)
                }
                Button(localized("暂停")) { service.pause(book: book) }
            default:
                if let message = statusMessage {
                    Label(message, systemImage: statusSymbol)
                        .foregroundStyle(statusIsError ? DSColor.destructive : DSColor.textSecondary)
                }
                if let plan {
                    if plan.isUpToDate {
                        Label(localized("摘要已涵盖目前的阅读进度。"), systemImage: "checkmark.circle")
                            .foregroundStyle(DSColor.textSecondary)
                    } else {
                        Button(actionTitle) { propose(plan) }
                    }
                } else if planError == nil {
                    ProgressView(localized("载入中…"))
                }
            }
        } footer: {
            Text(localized("只整理已读、且本机有正文的章节；离开此页会暂停，已完成的部分会保留。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private func volumeSection(_ plan: AIBookSummaryPlan) -> some View {
        Section {
            ForEach(plan.readVolumes.reversed()) { volume in
                NavigationLink {
                    AIVolumeSummaryView(volume: volume, through: plan.throughChapter, record: record)
                } label: {
                    LabeledContent {
                        Text(status(of: volume, through: plan.throughChapter))
                            .foregroundStyle(DSColor.textSecondary)
                    } label: {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(AIBookSummaryPlanner.title(of: volume))
                                .foregroundStyle(DSColor.textPrimary)
                            if volume.title != nil {
                                Text(String(format: localized("第 %1$d–%2$d 章"), volume.chapters.lowerBound + 1,
                                            min(volume.chapters.upperBound, plan.throughChapter) + 1))
                                    .font(DSFont.footnote)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text(localized("分卷"))
                .foregroundStyle(DSColor.textSecondary)
        }
        .interfaceSectionSurface()
    }

    private var actionTitle: String {
        switch run {
        case .paused, .budgetReached: return localized("继续整理")
        default: return record.book == nil && record.digests.isEmpty ? localized("整理摘要") : localized("更新摘要")
        }
    }

    private func status(of volume: AIBookVolume, through: Int) -> String {
        guard let summary = record.volumes[volume.id] else { return localized("未摘要") }
        return summary.throughChapter >= min(volume.chapters.upperBound, through) ? localized("已摘要") : localized("部分摘要")
    }

    private var statusMessage: String? {
        if let planError { return planError }
        switch run {
        case .budgetReached: return localized("已用完这次确认的呼叫次数，已暂停。")
        case .paused: return localized("已暂停，已完成的部分会保留。")
        case let .failed(message): return message
        case .idle, .running: return nil
        }
    }
    private var statusIsError: Bool {
        if planError != nil { return true }
        if case .failed = run { return true }
        return false
    }
    private var statusSymbol: String { statusIsError ? "exclamationmark.triangle" : "pause.circle" }

    // MARK: - Consent

    private func consent(_ proposal: Proposal) -> some View {
        let plan = proposal.plan
        let chapters = Set(plan.batches.flatMap { $0.parts.map(\.order) }).count
        return NavigationStack {
            Form {
                Section {
                    ThemedLabeledContent(localized("生成服务"), value: proposal.service.name)
                    ThemedLabeledContent(localized("生成模型"), value: proposal.service.model)
                    ThemedLabeledContent(localized("要整理的章节"), value: "\(chapters)")
                    ThemedLabeledContent(localized("预计模型呼叫"), value: "\(plan.estimatedCalls)")
                    ThemedLabeledContent(localized("送出的正文"), value: String(format: localized("约 %d 字"), plan.sourceUTF16))
                    if !plan.missingChapters.isEmpty {
                        ThemedLabeledContent(localized("缺少正文的章节"), value: "\(plan.missingChapters.count)")
                    }
                } footer: {
                    Text(localized("会把这些章节的本机正文分批传送到你的 AI 服务，可能产生费用。超过预计次数时会先暂停。"))
                        .dsSectionFooter()
                }
                .interfaceSectionSurface()
                Section {
                    Button(localized("开始整理")) {
                        self.proposal = nil
                        do { try service.start(plan: plan, source: adapter) } catch { planError = error.localizedDescription }
                    }
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .themedAppSurface(for: .settings)
            .navigationTitle(localized("确认整理摘要"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { self.proposal = nil } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(localized("取消"))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func propose(_ plan: AIBookSummaryPlan) {
        do {
            proposal = Proposal(plan: plan, service: try service.service())
            planError = nil
        } catch { planError = error.localizedDescription }
    }

    private func refreshPlan() async {
        do { plan = try await service.plan(source: adapter); planError = nil }
        catch { planError = error.localizedDescription }
    }
}

/// One volume: its summary, then the chapter digests it was written from.
private struct AIVolumeSummaryView: View {
    let volume: AIBookVolume
    let through: Int
    let record: AIBookSummaryRecord

    private var digests: [AIChapterDigest] {
        volume.chapters.filter { $0 <= through }.compactMap { record.digests[$0] }
    }

    var body: some View {
        List {
            Section {
                if let summary = record.volumes[volume.id] {
                    AIAnswerMarkdownView(text: summary.text)
                        .padding(.vertical, DSSpacing.xs)
                } else {
                    Text(localized("这一卷还没有摘要。"))
                        .foregroundStyle(DSColor.textSecondary)
                }
            } footer: {
                if let summary = record.volumes[volume.id] {
                    Text(String(format: localized("涵盖到第 %d 章"), summary.throughChapter + 1))
                        .dsSectionFooter()
                }
            }
            .interfaceSectionSurface()
            if !digests.isEmpty {
                Section {
                    ForEach(digests, id: \.order) { digest in
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(digest.title ?? String(format: localized("第 %d 章"), digest.order + 1))
                                .font(DSFont.subheadline.weight(.semibold))
                                .foregroundStyle(DSColor.textPrimary)
                            Text(digest.text)
                                .font(DSFont.body)
                                .foregroundStyle(DSColor.textPrimary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, DSSpacing.xs)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text(localized("逐章摘要"))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .interfaceSectionSurface()
            }
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(AIBookSummaryPlanner.title(of: volume))
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AIBookSummaryView(adapter: AIBookContentAdapter(bookID: UUID(), chapters: [], textForChapter: { _ in nil }))
    }
}
