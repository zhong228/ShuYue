import Foundation

enum AIReadingEvidence {
    /// Marks the reader's own selection among the evidence. The prompt puts it in
    /// `<selected-text>`: sent as plain reading context, a model asked to translate 「選取文字」
    /// could not tell which passage that was, said so, and explained the whole context instead.
    static let selectionIDPrefix = "selection:"

    static func collect(context: AIQuestionContext, index: AIBookRetrievalIndex) throws -> [AIQuestionEvidence] {
        if let selection = context.selection {
            guard selection.validated(in: context.source, boundary: context.boundary),
                  context.source.chunkSections.indices.contains(selection.spineIndex) else { throw LLMError.providerError(localized("选文已变更或超出目前阅读范围，请重新选取。")) }
            let section = context.source.chunkSections[selection.spineIndex]
            var chunk = AIContentChunk(id: selectionIDPrefix + "\(selection.spineIndex):\(selection.range.location):\(selection.range.length)",
                bookID: context.bookID, sectionID: section.id, ordinal: 0, text: selection.text,
                start: .init(spineIndex: selection.spineIndex, charOffset: selection.range.location, progress: 0),
                end: .init(spineIndex: selection.spineIndex, charOffset: NSMaxRange(selection.range), progress: 0))
            chunk.sourceVersion = context.source.contentFingerprint
            let selected = AIQuestionEvidence(chunk: chunk, parentChunkID: chunk.id, kind: .currentPosition)
            let entireChapter = context.customPrompt?.context == .chapter
            let neighbors = index.chunks.filter {
                $0.start.spineIndex == selection.spineIndex && context.boundary.contains($0) &&
                (entireChapter || ($0.end.charOffset >= max(0, selection.range.location - 800) && $0.start.charOffset <= NSMaxRange(selection.range) + 800))
            }.map { AIQuestionEvidence(chunk: $0, parentChunkID: $0.id, kind: .adjacent) }
            let prefix = entireChapter ? AIQuestionSourceReader.prefixes(index: index, context: context, query: "current passage") : []
            return AIQuestionSourceReader.deduplicated([selected] + neighbors + prefix, context: context)
        }
        if context.action == .chapterSummary || context.customPrompt?.context == .chapter {
            let spine = context.source.boundary().spineIndex
            let chunks = index.chunks.filter { $0.start.spineIndex == spine && context.boundary.contains($0) }
                .map { AIQuestionEvidence(chunk: $0, parentChunkID: $0.id, kind: .currentPosition) }
            return AIQuestionSourceReader.deduplicated(chunks + AIQuestionSourceReader.prefixes(index: index, context: context, query: "current passage"), context: context)
        }
        if context.action == .recap {
            // 前情回顾：整理读者已读的最近片段。阅读进度边界若尚未同步到 AI 源（例如在书首、
            // 或读取进度还没传过来），严格的边界过滤会拿不到任何素材，使回顾一直返回空结果。
            // 这里在严格过滤拿不到内容时，回退到当前章节之前（整本模式下为整本）的索引片段，
            // 保证前情回顾始终有内容可整理，而不是只显示「检索结果不足以确认」。
            let strict = index.chunks.filter { context.boundary.contains($0) && $0.start.spineIndex <= context.boundary.spineIndex }
            let safe = strict.isEmpty
                ? index.chunks.filter { context.boundary.wholeBook || $0.start.spineIndex <= context.boundary.spineIndex }
                : strict
            return AIQuestionSourceReader.deduplicated(safe.suffix(12).map { .init(chunk: $0, parentChunkID: $0.id, kind: .currentPosition) } +
                AIQuestionSourceReader.prefixes(index: index, context: context, query: "current passage"), context: context)
        }
        // Explicit chapter requests read that chapter's allowed body, even when the
        // question contains no words found in its prose. The loader uses this same resolver.
        let chapters = Set(requestedChapters(context))
        if !chapters.isEmpty {
            let chunks = index.chunks.filter { chapters.contains($0.start.spineIndex) && context.boundary.contains($0) }
                .map { AIQuestionEvidence(chunk: $0, parentChunkID: $0.id, kind: .initial) }
            let prefix = chapters.contains(context.boundary.spineIndex)
                ? AIQuestionSourceReader.prefixes(index: index, context: context, query: "current passage") : []
            return AIQuestionSourceReader.deduplicated(chunks + prefix, context: context)
        }
        return []
    }

    /// Resolve against actual TOC titles, never by treating a chapter number as a spine
    /// index (front matter and volumes make that unsafe). Callers still apply the boundary.
    static func requestedChapters(_ context: AIQuestionContext) -> [Int] {
        guard context.action == .question || context.customPrompt?.context == .book else { return [] }
        let question = AIBM25Index.searchText(context.question)
        let titles = context.source.chunkSections.map {
            AIBM25Index.searchText($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let pattern = #"(?:第\s*([0-9零〇一二两三四五六七八九十百千万]+)\s*[章回节]|\bchapter\s+([0-9]+)(?![a-z0-9]))"#
        guard let references = try? NSRegularExpression(pattern: pattern),
              let heading = try? NSRegularExpression(pattern: "^" + pattern) else { return [] }
        let numbers = Set(chapterNumbers(in: question, expression: references))
        let titleNumbers = titles.map { chapterNumbers(in: $0, expression: heading).first }
        let titleCounts = Dictionary(titles.map { ($0, 1) }, uniquingKeysWith: +)
        var indicesByNumber: [Int: [Int]] = [:]
        for (index, number) in titleNumbers.enumerated() {
            if let number { indicesByNumber[number, default: []].append(index) }
        }
        var matches: [Int] = []
        // Prefer explicit full titles; duplicate titles remain ambiguous.
        for (index, title) in titles.enumerated() where title.count > 1 {
            let titleRange = NSRange(title.startIndex..., in: title)
            let isBareNumber = heading.firstMatch(in: title, range: titleRange)?.range == titleRange
            if isBareNumber, let number = titleNumbers[index], (indicesByNumber[number]?.count ?? 0) != 1 { continue }
            let prefix = title.first.map { $0.isASCII && ($0.isLetter || $0.isNumber) } == true ? "(?<![a-z0-9])" : ""
            let suffix = title.last.map { $0.isASCII && ($0.isLetter || $0.isNumber) } == true ? "(?![a-z0-9])" : ""
            if titleCounts[title] == 1,
               question.range(of: prefix + NSRegularExpression.escapedPattern(for: title) + suffix, options: .regularExpression) != nil {
                matches.append(index)
            }
        }
        for number in numbers.sorted() {
            let candidates = indicesByNumber[number] ?? []
            // Numbering can restart in another volume. Do not silently choose one.
            if candidates.count == 1, let index = candidates.first, !matches.contains(index) { matches.append(index) }
        }
        return Array(matches.prefix(max(0, context.budget.maximumQueries)))
    }

    private static func chapterNumbers(in text: String, expression: NSRegularExpression) -> [Int] {
        expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            for group in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: group), in: text) {
                    return chapterNumber(String(text[range]))
                }
            }
            return nil
        }
    }

    private static func chapterNumber(_ text: String) -> Int? {
        guard !text.isEmpty, text.count <= 8 else { return nil }
        if let arabic = Int(text) { return arabic }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
                                      "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if text.allSatisfy({ digits[$0] != nil }) {
            return text.reduce(0) { $0 * 10 + (digits[$1] ?? 0) }
        }
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1_000, "万": 10_000]
        var total = 0, section = 0, digit = 0
        for character in text {
            if let value = digits[character] { digit = value }
            else if let unit = units[character] {
                if unit == 10_000 { total += max(1, section + digit) * unit; section = 0 }
                else { section += max(1, digit) * unit }
                digit = 0
            } else { return nil }
        }
        return total + section + digit
    }

    static func instruction(_ context: AIQuestionContext) -> String {
        let task: String
        switch context.action {
        case .question: task = "回答读者的问题，延续安全的对话背景。"
        case .explain, .lookup: task = "解释选取文字在原文中的意思、指代及必要背景，先给简洁说明。"
        case .translate:
            let language = context.answerLanguage.promptName
            task = "把选取文字翻译成\(language)，保留段落和语气，必要译注另外列出。原文已经是\(language)时：文言、古文译成现代白话；否则说明它已是\(language)，再用白话解释难懂的地方。"
        case .chapterSummary: task = "摘要目前章节在允许范围内的内容；若提供的正文不完整，明确说明只涵盖部分。"
        case .recap: task = "以最近已读片段整理前情，帮助读者接续阅读，不声称涵盖全部剧情。"
        case .custom: task = "依读者的自订任务分析提供的内容。"
        case .annotationReview: task = "整理读者在已读范围内的划线与笔记：依主题、人物或情节归类，说明每处划线在故事里的作用，并回应笔记中的想法。笔记是读者的观点，不是书中事实。"
        }
        let selection = context.selection == nil ? "" : "读者选取的文字在 selected-text 标记里，只有它是「选取文字」；其他片段是它前后的上下文。\n"
        return task + "\n" + selection + "回答里不要提到 selected-text、current-reading-context 这些资料标记。\n" + (context.allowsBackgroundKnowledge ? "概念、典故与翻译可使用模型知识，另以『补充解释』标示；不得以模型记忆补写本书情节。找不到书中事实时说明无法确认。" : "书中事实只依提供的原文。") +
            (context.boundary.wholeBook ? "" : "\n禁止揭露目前已读原文之外的情节、身分或结局，即使你知道本书。")
    }
}

/// Keeps protocol markers out of partial answers, even when split across network events.
struct AIAnswerStreamDisplay {
    private var assessment: AISelfAssessmentStreamParser
    private var pending = ""
    init(nonce: String) { assessment = .init(nonce: nonce) }

    mutating func consume(_ delta: String) -> String {
        pending += assessment.consume(delta)
        var output = ""
        while let start = pending.firstIndex(of: "[") {
            output += pending[..<start]
            pending = String(pending[start...])
            guard let end = pending.firstIndex(of: "]") else { return output }
            let marker = String(pending[pending.index(after: pending.startIndex)..<end])
            if marker.range(of: #"^S[0-9]*$"#, options: .regularExpression) == nil && !marker.hasPrefix("fragment:") && !marker.hasPrefix(AIReadingEvidence.selectionIDPrefix) {
                output += pending[...end]
            }
            pending = String(pending[pending.index(after: end)...])
        }
        output += pending
        pending = ""
        return output
    }
}
