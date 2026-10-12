import Foundation

enum AIReadingEvidence {
    /// Marks the reader's own selection among the evidence. The prompt puts it in
    /// `<selected-text>`: sent as plain reading context, a model asked to translate 「選取文字」
    /// could not tell which passage that was, said so, and explained the whole context instead.
    static let selectionIDPrefix = "selection:"

    static func collect(context: AIQuestionContext, index: AIBookRetrievalIndex) throws -> [AIQuestionEvidence] {
        if let selection = context.selection {
            guard selection.validated(in: context.source, boundary: context.boundary) else { throw LLMError.providerError(localized("選文已變更或超出目前閱讀範圍，請重新選取。")) }
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
            let safe = index.chunks.filter { context.boundary.contains($0) && $0.start.spineIndex <= context.source.boundary().spineIndex }
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
        case .question: task = "回答讀者的問題，延續安全的對話背景。"
        case .explain, .lookup: task = "解釋選取文字在原文中的意思、指代及必要背景，先給簡潔說明。"
        case .translate:
            let language = context.answerLanguage.promptName
            task = "把選取文字翻譯成\(language)，保留段落和語氣，必要譯註另外列出。原文已經是\(language)時：文言、古文譯成現代白話；否則說明它已是\(language)，再用白話解釋難懂的地方。"
        case .chapterSummary: task = "摘要目前章節在允許範圍內的內容；若提供的正文不完整，明確說明只涵蓋部分。"
        case .recap: task = "以最近已讀片段整理前情，幫助讀者接續閱讀，不聲稱涵蓋全部劇情。"
        case .custom: task = "依讀者的自訂任務分析提供的內容。"
        case .annotationReview: task = "整理讀者在已讀範圍內的劃線與筆記：依主題、人物或情節歸類，說明每處劃線在故事裡的作用，並回應筆記中的想法。筆記是讀者的觀點，不是書中事實。"
        }
        let selection = context.selection == nil ? "" : "讀者選取的文字在 selected-text 標記裡，只有它是「選取文字」；其他片段是它前後的上下文。\n"
        return task + "\n" + selection + "回答裡不要提到 selected-text、current-reading-context 這些資料標記。\n" + (context.allowsBackgroundKnowledge ? "概念、典故與翻譯可使用模型知識，另以『補充解釋』標示；不得以模型記憶補寫本書情節。找不到書中事實時說明無法確認。" : "書中事實只依提供的原文。") +
            (context.boundary.wholeBook ? "" : "\n禁止揭露目前已讀原文之外的情節、身分或結局，即使你知道本書。")
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
