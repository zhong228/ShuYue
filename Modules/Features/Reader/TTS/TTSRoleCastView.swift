import AVFoundation
import SwiftUI

/// 多角色朗讀 — assigns a voice to each character so a novel is read as a cast rather
/// than by one narrator.
///
/// Scoped to the open book: the same name is a different person in a different novel, and
/// the speaker list is read out of the chapter being listened to, so the names on screen
/// are the ones about to be spoken.
struct TTSRoleCastView: View {
    let bookID: UUID
    /// Speakers found in the chapter being read, in the order they first speak.
    let detectedSpeakers: [String]
    /// The book, for building character cards from here — the aliases they produce are what
    /// stop one person being cast as three.
    let adapter: AIBookContentAdapter
    /// How far the reader has got, so the character list can default to people who have
    /// actually appeared rather than spoiling the rest of the book.
    let progress: Double

    @ObservedObject private var gs = GlobalSettings.shared
    @ObservedObject private var cards = AICharacterCardStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAISettings = false
    @State private var showResetConfirmation = false
    @ObservedObject private var rosters = AISpeakerRosterStore.shared
    @ObservedObject private var subscription = SubscriptionStore.shared
    /// Resolved on appear: `isConfigured` reads the Keychain, and `body` runs often.
    @State private var aiConfigured = false

    private var family: TTSVoiceFamily { .active() }
    private var cast: [String: String] { TTSRoleVoiceCast.cast(forBook: bookID, in: gs.ttsRoleVoices) }

    /// Characters cast earlier that this chapter does not happen to include. Without this
    /// they would look un-cast, and re-casting them would silently replace a deliberate
    /// choice made while reading a different chapter.
    private var castElsewhere: [String] {
        cast.keys.filter { !detectedSpeakers.contains($0) }.sorted()
    }

    var body: some View {
        Form {
            enableSection
            // Outside the multi-role gate on purpose: character cards are worth having
            // before a second voice exists — they are a reading aid in their own right, and
            // the aliases have to be there the moment the reader does import one. Hiding
            // them behind the toggle made them unreachable for anyone on a single source.
            // Character cards are made by AI, which needs Pro; cards made earlier keep
            // working either way.
            if ReaderPremiumVisibilityPolicy(isProActive: subscription.isProActive).allowsAI {
                aliasSection
            }
            if supportsMultiRole {
                detectedSection
                if !castElsewhere.isEmpty { elsewhereSection }
            }
        }
        .softScrollEdges()
        .navigationTitle(localized("多角色朗读"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .onAppear {
            aiConfigured = AIAssistantService.shared.isConfigured
            cards.loadIfNeeded(forBook: bookID)
            rosters.loadIfNeeded(forBook: bookID)
        }
        .sheet(isPresented: $showAISettings, onDismiss: {
            aiConfigured = AIAssistantService.shared.isConfigured
        }) {
            AISettingsView()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localized("重设")) {
                    showResetConfirmation = true
                }
                // Dead only when there is genuinely nothing for this book: no cast, no
                // roster, no cards. It used to test the cast alone, so it sat greyed out
                // while a roster and a pile of character cards existed behind it.
                .disabled(!hasAnythingToReset)
            }
        }
        .confirmationDialog(
            localized("重设这本书的角色设定？"),
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("重设"), role: .destructive) { resetBook() }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("会清掉这本书的配音、AI 整理的角色名单，以及所有人物卡。书本身和听书设定不受影响。"))
        }
    }

    private var hasAnythingToReset: Bool {
        !cast.isEmpty
            || !rosters.roster(forBook: bookID).isEmpty
            || !cards.profiles(forBook: bookID).isEmpty
    }

    private func resetBook() {
        gs.ttsRoleVoices = TTSRoleVoiceCast.clearing(bookID: bookID, in: gs.ttsRoleVoices)
        rosters.clear(forBook: bookID)
        for profile in cards.profiles(forBook: bookID) {
            cards.remove(name: profile.name, forBook: bookID)
        }
    }

    // MARK: - Sections

    private var enableSection: some View {
        Section {
            Toggle(localized("多角色朗读"), isOn: $gs.ttsMultiRoleEnabled)
                .disabled(!supportsMultiRole)
        } footer: {
            Text(enableFooterText).dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    /// Re-read from the live source list rather than the default argument, so importing a
    /// second voice enables the toggle without leaving this screen.
    private var supportsMultiRole: Bool {
        family.supportsMultiRole(importedSourceCount: gs.importedTTSSources.count)
    }

    private var enableFooterText: String {
        switch family {
        case .system:
            return localized("为每个角色指派不同的系统语音。未指派的角色与旁白共用同一个声音。")
        case .edge:
            return localized("为每个角色指派不同的微软线上语音。角色越多，每章需要合成的片段也越多。")
        case .bookSource:
            // One source is one voice, so the cast is the list of imported sources. A reader
            // with only one has nothing to switch between — which is a missing import, not
            // an unsupported engine.
            return supportsMultiRole
                ? localized("为每个角色指派不同的汇入语音源。角色越多，每章需要的请求也越多。")
                : localized("汇入的语音源一个就是一个声音，目前只汇入了一个。到语音朗读设定再汇入几个（语音包通常一个音色一笔），就能指派给不同角色。")
        }
    }

    /// Why the same character can end up with three voices, and what to do about it.
    ///
    /// The dialogue heuristic reads a name out of the prose; it cannot know that 張若塵,
    /// 若塵 and 塵哥 are one person. The AI character cards are the only thing that can tell
    /// it, so this is where that connection is made visible — including when the AI is not
    /// set up, which is the common case and must not look like a malfunction.
    @ViewBuilder
    private var aliasSection: some View {
        let safeProfiles = cards.profiles(forBook: bookID).filter { $0.isSafe(at: adapter.boundary()) }
        let aliasCount = AICharacterAliasTable.aliasMap(for: safeProfiles).count
        let cardCount = safeProfiles.count
        Section {
            if !aiConfigured {
                Button {
                    showAISettings = true
                } label: {
                    LabeledContent(localized("设定 AI 助手")) {
                        Text(localized("未设定"))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
            NavigationLink {
                AICharacterListView(bookID: bookID, adapter: adapter, progress: progress)
            } label: {
                LabeledContent(localized("人物卡")) {
                    Text(
                        cardCount == 0
                            ? localized("还没有人物卡")
                            : String(format: localized("%1$d 张人物卡、%2$d 个别名"), cardCount, aliasCount)
                    )
                    .foregroundStyle(DSColor.textSecondary)
                }
            }
        } header: {
            Text(localized("角色识别"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(
                aiConfigured
                    ? localized("整理人物卡之后，同一个人的不同称呼（张若尘／若尘／尘哥）会归成同一个声音。")
                    : localized("没有 AI 也能用，只是同一个人的不同称呼会各拿一个声音。")
            )
            .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var detectedSection: some View {
        Section {
            if detectedSpeakers.isEmpty {
                Text(localized("这一章没有侦测到对话。"))
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            } else {
                ForEach(detectedSpeakers, id: \.self) { speaker in
                    speakerRow(speaker)
                }
            }
        } header: {
            Text(localized("本章角色"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("角色是从「某某说道：「…」」这类叙述里读出来的，判断不出来的对话会用旁白的声音。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    private var elsewhereSection: some View {
        Section {
            ForEach(castElsewhere, id: \.self) { speaker in
                speakerRow(speaker)
            }
        } header: {
            Text(localized("其他已指派的角色"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("这些角色在本书其他章节出现过。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    // MARK: - Rows

    private func speakerRow(_ speaker: String) -> some View {
        let assigned = cast[speaker].flatMap(TTSRoleVoice.init(storageValue:))
        return NavigationLink {
            TTSRoleVoicePickerView(bookID: bookID, speaker: speaker)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Text(speaker)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: DSSpacing.sm)
                Text(voiceLabel(for: assigned))
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
            }
        }
        // One focus stop per character, reading the name and the voice together, rather
        // than the two labels VoiceOver would otherwise land on separately.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(speaker)，\(voiceLabel(for: assigned))")
        .accessibilityHint(localized("选择这个角色的声音"))
    }

    /// What a row says about a character's voice — including the case the whole tagging
    /// scheme exists for: cast with a voice the running engine cannot speak.
    private func voiceLabel(for voice: TTSRoleVoice?) -> String {
        guard let voice else { return localized("旁白") }
        switch (voice, family) {
        case let (.system(identifier), .system):
            return AVSpeechSynthesisVoice(identifier: identifier)?.name ?? localized("语音已移除")
        case let (.edge(voiceID), .edge):
            return EdgeTTSVoice.voice(id: voiceID)?.displayName ?? localized("语音已移除")
        case (.bookSource, .bookSource):
            return voice.importedSource()?.name ?? localized("语音已移除")
        default:
            return localized("目前的语音来源不支援")
        }
    }
}

/// Picks one voice for one character, from whichever catalogue the running engine uses.
struct TTSRoleVoicePickerView: View {
    let bookID: UUID
    let speaker: String

    @ObservedObject private var gs = GlobalSettings.shared
    @Environment(\.dismiss) private var dismiss

    private var family: TTSVoiceFamily { .active() }
    private var current: TTSRoleVoice? {
        TTSRoleVoiceCast.cast(forBook: bookID, in: gs.ttsRoleVoices)[speaker]
            .flatMap(TTSRoleVoice.init(storageValue:))
    }

    var body: some View {
        Form {
            Section {
                row(title: localized("旁白"), isSelected: current == nil) { assign(nil) }
            } footer: {
                Text(localized("与没有指派声音的角色、以及旁白文字使用同一个声音。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            switch family {
            case .system: systemVoiceSections
            case .edge: edgeVoiceSection
            case .bookSource: importedSourceSection
            }
        }
        .softScrollEdges()
        .navigationTitle(speaker)
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
    }

    /// Each imported voice source is one voice.
    ///
    /// A voice pack ships one entry per speaker, so the list the reader already sees under
    /// 語音朗讀設定 is exactly the cast they can draw from.
    private var importedSourceSection: some View {
        Section {
            ForEach(gs.importedTTSSources) { source in
                row(
                    title: source.name,
                    isSelected: current == .bookSource(sourceID: source.id)
                ) {
                    assign(.bookSource(sourceID: source.id))
                }
            }
        } header: {
            Text(localized("汇入的语音源"))
                .foregroundStyle(DSColor.textSecondary)
        } footer: {
            Text(localized("每个汇入的语音源就是一个声音。想要更多音色，就到语音朗读设定汇入更多来源。"))
                .dsSectionFooter()
        }
        .interfaceSectionSurface()
    }

    @ViewBuilder
    private var systemVoiceSections: some View {
        ForEach(SystemTTSVoiceCatalog.groupedByLanguage()) { group in
            Section {
                ForEach(group.voices, id: \.identifier) { voice in
                    row(
                        title: voice.name,
                        detail: SystemTTSVoiceCatalog.qualityLabel(for: voice),
                        isSelected: current?.systemIdentifier == voice.identifier
                    ) {
                        assign(.system(identifier: voice.identifier))
                    }
                }
            } header: {
                Text(group.displayName)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .interfaceSectionSurface()
        }
    }

    private var edgeVoiceSection: some View {
        Section {
            ForEach(EdgeTTSVoice.voices) { voice in
                row(
                    title: voice.displayName,
                    isSelected: current?.edgeVoice?.id == voice.id
                ) {
                    assign(.edge(voiceID: voice.id))
                }
            }
        } header: {
            Text(localized("微软线上语音"))
                .foregroundStyle(DSColor.textSecondary)
        }
        .interfaceSectionSurface()
    }

    private func row(
        title: String,
        detail: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        var traits: AccessibilityTraits = .isButton
        if isSelected { _ = traits.insert(.isSelected) }
        return Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(DSColor.textPrimary)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                Spacer(minLength: DSSpacing.sm)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DSColor.accent)
                        // Decorative: the selected state is already in the traits, and
                        // VoiceOver would otherwise read the raw symbol name.
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(traits)
    }

    private func assign(_ voice: TTSRoleVoice?) {
        gs.ttsRoleVoices = TTSRoleVoiceCast.setting(
            voiceIdentifier: voice?.storageValue,
            forSpeaker: speaker,
            bookID: bookID,
            in: gs.ttsRoleVoices
        )
        dismiss()
    }
}

#Preview("角色列表") {
    NavigationStack {
        TTSRoleCastView(
            bookID: UUID(),
            detectedSpeakers: ["张若尘", "池瑶", "齐源老道"],
            adapter: AIBookContentAdapter(bookID: UUID(), chapters: [], textForChapter: { _ in nil }),
            progress: 0.42
        )
    }
}

#Preview("没有侦测到对话") {
    NavigationStack {
        TTSRoleCastView(
            bookID: UUID(),
            detectedSpeakers: [],
            adapter: AIBookContentAdapter(bookID: UUID(), chapters: [], textForChapter: { _ in nil }),
            progress: 0.42
        )
    }
}
