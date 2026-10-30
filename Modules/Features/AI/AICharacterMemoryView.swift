import SwiftUI

struct AICharacterMemoryView: View {
    let adapter: AIBookContentAdapter
    var onOpenCitation: ((LLMCitation) -> Void)? = nil
    @ObservedObject private var service = AICharacterMemoryService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var buildWholeBook = false
    @State private var budget = AIMemoryBudget()
    @State private var proposal: AIMemoryJob?
    @State private var proposalCoverage: AIMemoryCoverage?
    @State private var projection = AIMemoryView(cards: [], aliases: [], approvedAliasIDs: [])
    @State private var loadedKey = ""
    @State private var query = ""
    @State private var page = 0
    @State private var error: String?
    @State private var viewingWholeBook = false
    @State private var chapterView = false
    @State private var viewChapter = 0
    @State private var allowFutureView = false
    @State private var confirmView = false
    @State private var confirmResume = false
    @State private var confirmClear = false
    @State private var additionalCalls = 0
    @State private var operation: Task<Void, Never>?
    @State private var selected: Selection?
    private struct Selection: Identifiable { let id: String }
    private enum ViewScope: Hashable { case reading, chapter, wholeBook }
    private var viewScope: ViewScope { viewingWholeBook ? .wholeBook : chapterView ? .chapter : .reading }
    /// Later chapters are a spoiler, so 查看後文 asks first and only takes effect once confirmed.
    private var viewScopeBinding: Binding<ViewScope> {
        Binding(get: { viewScope }, set: { value in
            selected = nil
            switch value {
            case .wholeBook: confirmView = true
            case .chapter: viewingWholeBook = false; allowFutureView = false; chapterView = true
            case .reading: viewingWholeBook = false; allowFutureView = false; chapterView = false
            }
        })
    }
    private var job: AIMemoryJob? { service.jobs[adapter.chunkBookID] }
    private var coverage: AIMemoryCoverage? { service.coverages[adapter.chunkBookID] }
    private var boundary: AIReadingBoundary {
        if viewingWholeBook { return adapter.boundary(wholeBook: true) }
        let chapter = min(viewChapter, maximumViewChapter)
        if chapterView, adapter.chunkSections.indices.contains(chapter) {
            let read = adapter.boundary()
            let offset = !allowFutureView && chapter == read.spineIndex ? read.utf16Offset : adapter.chunkSections[chapter].text.utf16.count
            return .init(sourceVersion: adapter.contentFingerprint, sectionID: adapter.chunkSections[chapter].id,
                spineIndex: chapter, utf16Offset: offset)
        }
        return adapter.boundary()
    }
    private var viewKey: String { "\(adapter.contentFingerprint)@\(boundary)@\(service.revisions[adapter.chunkBookID] ?? 0)" }
    private var visible: AIMemoryView { loadedKey == viewKey ? projection : .init(cards: [], aliases: [], approvedAliasIDs: []) }
    private var maximumViewChapter: Int { max(0, min(adapter.chunkSections.count - 1, allowFutureView ? adapter.chunkSections.count - 1 : adapter.boundary().spineIndex)) }

    var body: some View {
        List {
            Section {
                Picker(localized("建档范围"), selection: $buildWholeBook) {
                    Text(localized("截至目前阅读位置")).tag(false)
                    Text(localized("本机可用全书正文")).tag(true)
                }
                DisclosureGroup(localized("进阶设定")) {
                Stepper(String(format: localized("总呼叫上限：%d"), budget.maximumCalls), value: $budget.maximumCalls, in: 1...100_000)
                Toggle(localized("截断时允许自动分拆一次"), isOn: Binding(get: { budget.automaticSplitDepth > 0 }, set: { budget.automaticSplitDepth = $0 ? 1 : 0 }))
                }
                Button(buildWholeBook ? localized("规划人物建档") : localized("整理已读人物")) { prepare() }.disabled(job?.state == .running)
            } footer: {
                Text(localized("建档会逐批传送允许范围内的本机正文到你的生成服务；开始前会再次列明模型与预算。"))
                    .dsSectionFooter()
            }
            if let job { jobSection(job) }
            if let error = error ?? service.failures[adapter.chunkBookID] {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(DSColor.destructive) }
            }
            Section {
                Picker(localized("查看范围"), selection: viewScopeBinding) {
                    Text(localized("截至目前阅读位置")).tag(ViewScope.reading)
                    Text(localized("按章节进度查看")).tag(ViewScope.chapter)
                    Text(localized("查看后文人物资料")).tag(ViewScope.wholeBook)
                }
                if viewScope == .chapter {
                    Stepper(String(format: localized("查看到第 %d 章"), viewChapter + 1), value: $viewChapter, in: 0...maximumViewChapter)
                }
                ThemedLabeledContent(localized("目前范围人物数"), value: "\(visible.count)")
            }
            Section {
                if loadedKey != viewKey {
                    ProgressView(localized("载入中…"))
                } else if visible.cards.isEmpty {
                    ContentUnavailableView {
                        UnavailableLabel(localized("此范围尚无人物资料"), systemImage: "person.text.rectangle")
                    }
                        .listRowBackground(Color.clear)
                }
                ForEach(visible.page(query: query, offset: page * 40)) { card in
                    Button { selected = Selection(id: card.id) } label: {
                        ThemedLabeledContent(card.names.joined(separator: "、"), value: String(format: localized("%d 笔经历记录"), card.facts.count))
                    }
                }
                if page > 0 { Button(localized("上一页")) { page -= 1 } }
                if !visible.page(query: query, offset: (page + 1) * 40).isEmpty { Button(localized("下一页")) { page += 1 } }
            } footer: {
                // About the cards themselves, so only once there are some.
                if !visible.cards.isEmpty {
                    Text(localized("这是模型抽取的结构化记录，不代表人物或事实全部正确；每项保留原文供核对。新别名不会自动送入问答或朗读。"))
                        .dsSectionFooter()
                }
            }
            Section {
                Button(localized("清除本书人物建档资料"), role: .destructive) { confirmClear = true }
            } footer: {
                Text(localized("清除不会删除正文、聊天或人工角色声音设定。"))
                    .dsSectionFooter()
            }
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("书中人物整理"))
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: localized("搜寻目前范围的人物"))
        .onChange(of: query) { _, _ in page = 0 }
        .task(id: adapter.contentFingerprint) {
            do { try await service.load(source: adapter) } catch { self.error = error.localizedDescription }
        }
        .task(id: viewKey) {
            let key = viewKey
            do {
                let view = try await service.view(source: adapter, boundary: boundary)
                guard !Task.isCancelled, key == viewKey else { return }
                projection = view; loadedKey = key
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: boundary) { _, _ in selected = nil; page = 0 }
        .onChange(of: adapter.contentFingerprint) { _, _ in selected = nil; proposal = nil; operation?.cancel(); service.pause(book: adapter.chunkBookID) }
        .onChange(of: scenePhase) { _, value in if value != .active { operation?.cancel(); service.pause(book: adapter.chunkBookID) } }
        .onDisappear { operation?.cancel(); service.pause(book: adapter.chunkBookID) }
        .sheet(item: $proposal) { job in consent(job) }
        .sheet(item: $selected) { selection in
            NavigationStack {
                AIMemoryCardView(entityID: selection.id, source: adapter, boundary: boundary, onOpenCitation: onOpenCitation)
            }
        }
        .confirmationDialog(localized("查看后文可能揭露人物身分与关系"), isPresented: $confirmView, titleVisibility: .visible) {
            Button(localized("确认查看后文")) { allowFutureView = true; viewingWholeBook = true }
            Button(localized("取消"), role: .cancel) {}
        }
        .confirmationDialog(localized("确认续跑与呼叫预算"), isPresented: $confirmResume, titleVisibility: .visible) {
            Button(localized("确认续跑")) { resume() }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("未保存的上一批可能已呼叫并计费；续跑可能再次计费，所有呼叫仍计入此工作的总预算。"))
        }
        .confirmationDialog(localized("清除本书人物建档资料？"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(localized("清除"), role: .destructive) { Task {
                do { try await service.clear(book: adapter.chunkBookID); projection = .init(cards: [], aliases: [], approvedAliasIDs: []) }
                catch { self.error = error.localizedDescription }
            } }
            Button(localized("取消"), role: .cancel) {}
        }
    }
    private func prepare() {
        error = nil
        Task {
            do {
                let job = try service.prepare(source: adapter, wholeBook: buildWholeBook, budget: budget)
                proposalCoverage = try await service.coverage(job: job, source: adapter)
                proposal = job
            } catch { self.error = error.localizedDescription }
        }
    }
    private func resume() {
        operation?.cancel()
        operation = Task { do { try await service.resume(source: adapter, acknowledgeUnknown: true, additionalCalls: additionalCalls); additionalCalls = 0; error = nil }
            catch { self.error = error.localizedDescription } }
    }
    private func jobSection(_ job: AIMemoryJob) -> some View {
        Section {
            ThemedLabeledContent(localized("建档状态"), value: state(job.state))
            if let coverage, coverage.plannedUnits > 0 {
                ProgressView(value: Double(coverage.committedUnits), total: Double(coverage.plannedUnits)) {
                    ThemedLabeledContent(localized("已保存批次"), value: "\(coverage.committedUnits) / \(coverage.plannedUnits)")
                }
            }
            ThemedLabeledContent(localized("模型呼叫"), value: "\(job.calls) / \(job.budget.maximumCalls)")
            if let failure = job.failure {
                Text(failure == "length" ? localized("抽取输出被截断，可分拆该批后再确认续跑。") :
                    AIMemoryFailure(rawValue: failure)?.localizedDescription ?? localized("该批抽取失败，未保存为成功。"))
                    .foregroundStyle(DSColor.destructive)
            }
            if job.state == .running { Button(localized("暂停建档")) { service.pause(book: adapter.chunkBookID) } }
            else if job.state != .completedAvailable {
                Stepper(String(format: localized("追加呼叫额度：%d"), additionalCalls), value: $additionalCalls, in: 0...100_000)
                Button(localized("续跑／重试未完成批次")) { confirmResume = true }
                if job.state == .failed {
                    Button(localized("分拆未完成批次")) { Task {
                        do { try await service.splitFailed(source: adapter) } catch { self.error = error.localizedDescription }
                    } }
                }
            }
            DisclosureGroup(localized("详细资料")) {
                ThemedLabeledContent(localized("生成模型"), value: job.model)
                if let coverage {
                    ThemedLabeledContent(localized("目录目标章节"), value: "\(job.targetChapters)")
                    ThemedLabeledContent(localized("可分析章节／已分析章节"), value: "\(coverage.availableChapters) / \(coverage.analyzedChapters)")
                    ThemedLabeledContent(localized("已保存主要正文 UTF-16"), value: "\(coverage.committedUTF16) / \(coverage.plannedUTF16)")
                    ForEach(coverage.missing, id: \.order) { chapter in
                        ThemedLabeledContent(String(format: localized("第 %d 章"), chapter.order + 1), value: missing(chapter.status))
                    }
                }
            }
        } footer: {
            Text(localized("离开此页或退到背景会暂停建档。缺少正文的章节不算完成，也不保证没有漏抽人物。"))
                .dsSectionFooter()
        }
    }
    private func consent(_ job: AIMemoryJob) -> some View {
        NavigationStack {
            Form {
                Section {
                    ThemedLabeledContent(localized("生成服务"), value: job.providerDisplayName)
                    ThemedLabeledContent(localized("生成模型"), value: job.model)
                    ThemedLabeledContent(localized("建档范围"), value: job.boundary.wholeBook ? localized("本机可用全书正文") : localized("截至目前阅读位置"))
                    ThemedLabeledContent(localized("初始批次数"), value: "\(job.units.count)")
                    ThemedLabeledContent(localized("总模型呼叫上限"), value: "\(job.budget.maximumCalls)")
                    ThemedLabeledContent(localized("token 数与金额估算"), value: localized("未知"))
                    DisclosureGroup(localized("详细资料")) {
                        ThemedLabeledContent(localized("每批输出 token 上限"), value: "\(job.budget.outputTokens)")
                        if let info = proposalCoverage {
                            ThemedLabeledContent(localized("可分析字元／UTF-16／bytes"), value: "\(info.characters) / \(info.plannedUTF16) / \(info.bytes)")
                            ThemedLabeledContent(localized("可重用已保存批次"), value: "\(info.committedUnits)")
                        }
                    }
                } footer: {
                    Text(localized("这会逐批传送正文，不只是问答命中的少数片段。全书范围可能包含后文；模型服务可能收费，没有价格或 tokenizer 资料时不估价。"))
                        .dsSectionFooter()
                }
                Section {
                    Button(localized("确认传送并开始建档")) {
                        proposal = nil
                        operation?.cancel()
                        operation = Task { do { try await service.start(confirmed: job, source: adapter) } catch { self.error = error.localizedDescription } }
                    }.disabled(job.units.isEmpty)
                }
            }
            .softScrollEdges()
            .themedAppSurface(for: .settings)
            .navigationTitle(localized("确认人物建档"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { proposal = nil } label: { Image(systemName: "xmark").accessibilityHidden(true) }.accessibilityLabel(localized("取消")) } }
        }
    }
    private func state(_ state: AIMemoryJob.State) -> String {
        switch state {
        case .running: return localized("正在逐批分析")
        case .completedAvailable: return localized("本机可用范围已分析")
        case .budgetPaused: return localized("预算用尽，已暂停")
        case .resultUnknown: return localized("上一批结果未知")
        case .failed: return localized("失败，等待重试")
        case .cancelled, .paused: return localized("已暂停")
        case .superseded: return localized("来源工作已更新")
        }
    }
    private func missing(_ status: AISourceManifest.Availability) -> String {
        switch status {
        case .available: return localized("正文已取得")
        case .notDownloaded: return localized("尚未下载")
        case .extractionFailed: return localized("正文抽取失败")
        case .unsupported: return localized("格式不支援正文抽取")
        }
    }
}

struct AIMemoryCardView: View {
    let entityID: String
    let source: AIBookContentAdapter
    let boundary: AIReadingBoundary
    let onOpenCitation: ((LLMCitation) -> Void)?
    var showsDone = true
    @ObservedObject private var service = AICharacterMemoryService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var view = AIMemoryView(cards: [], aliases: [], approvedAliasIDs: [])
    @State private var loading = true
    @State private var page = 0
    @State private var error: String?
    private var card: AIMemoryCard? { view.cards.first { $0.entityIDs.contains(entityID) } }
    var body: some View {
        List {
            if let card {
                Section {
                    Text(card.names.joined(separator: "、")).font(DSFont.title3).foregroundStyle(DSColor.textPrimary)
                    if card.mentions.allSatisfy(\.unresolved) { Text(localized("包含未决称呼，身分仍待确认。")).foregroundStyle(DSColor.textSecondary) }
                    if let earliest = card.earliest {
                        Text(localized("目前找到最早的明确提及"))
                            .foregroundStyle(DSColor.textSecondary)
                        evidence(earliest.evidence)
                    }
                }
                Section {
                    ForEach(card.facts.dropFirst(page * 30).prefix(30)) { fact in
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(kind(fact.kind)).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                            Text(fact.text).textSelection(.enabled).foregroundStyle(DSColor.textPrimary)
                            ForEach(fact.evidence) { evidence($0) }
                        }
                    }
                    if page > 0 { Button(localized("上一页")) { page -= 1 } }
                    if (page + 1) * 30 < card.facts.count { Button(localized("下一页")) { page += 1 } }
                } header: {
                    Text(localized("经历与关系（原文揭露顺序）"))
                        .foregroundStyle(DSColor.textSecondary)
                } footer: {
                    if onOpenCitation == nil {
                        Text(localized("此入口无法精准跳转，请依章节与引文核对。"))
                            .dsSectionFooter()
                    }
                }
                ForEach(card.aliases) { alias in
                    Section {
                        let otherIDs = [alias.first, alias.second]
                        Text(view.cards.filter { !$0.entityIDs.isDisjoint(with: otherIDs) }.flatMap(\.names).joined(separator: "、"))
                            .foregroundStyle(DSColor.textPrimary)
                        Text(localized("是否同一人物：请核对原文"))
                            .foregroundStyle(DSColor.textSecondary)
                        ForEach(alias.evidence) { evidence($0) }
                        Button(view.approvedAliasIDs.contains(alias.id) ? localized("撤回身分合并") : localized("确认是同一人物")) {
                            Task { do { try await service.decide(alias: alias, approved: !view.approvedAliasIDs.contains(alias.id), source: source, boundary: boundary) }
                                catch { self.error = error.localizedDescription } }
                        }
                    } footer: {
                        Text(localized("同名或模型信心不是合并依据；确认只影响此揭露范围之后的检视，原始提及与事实仍保留。"))
                            .dsSectionFooter()
                    }
                }
            } else if loading { ProgressView(localized("载入中…")) }
            else { ContentUnavailableView {
                UnavailableLabel(localized("此范围尚无人物资料"), systemImage: "person.crop.circle")
            } }
            if let error { Text(error).foregroundStyle(DSColor.destructive) }
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("人物经历与证据"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar { if showsDone { ToolbarItem(placement: .confirmationAction) { Button { dismiss() } label: { Image(systemName: "checkmark").accessibilityHidden(true) }.accessibilityLabel(localized("完成")) } } }
        .task(id: service.revisions[source.chunkBookID]) {
            loading = true
            do { view = try await service.view(source: source, boundary: boundary) } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
    @ViewBuilder private func evidence(_ proof: AIMemoryEvidence) -> some View {
        Text(String(format: localized("第 %d 章"), proof.span.spine + 1)).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
        Text(proof.quote).font(DSFont.callout).textSelection(.enabled).foregroundStyle(DSColor.textPrimary)
        // Without a jump handler the section footer says so once; here only a quote that
        // cannot be located, among ones that can, needs its own note.
        if let onOpenCitation {
            if let citation = proof.citation(source: source) {
                Button(localized("跳到原文")) { dismiss(); onOpenCitation(citation) }
            } else {
                Text(localized("此入口无法精准跳转，请依章节与引文核对。"))
                    .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            }
        }
    }
    private func kind(_ kind: AIMemoryFact.Kind) -> String {
        switch kind {
        case .narration: return localized("原文叙述")
        case .statement: return localized("角色发言／自述")
        case .rumor: return localized("传闻／怀疑")
        case .interpretation: return localized("模型解读")
        case .correction: return localized("后文反驳／修正")
        case .relationship: return localized("关系记录")
        }
    }
}

#Preview {
    NavigationStack { AICharacterMemoryView(adapter: .init(bookID: UUID(), chapters: [], textForChapter: { _ in nil })) }
}
