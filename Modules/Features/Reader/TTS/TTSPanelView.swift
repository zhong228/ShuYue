import SwiftUI

#Preview {
    TTSPanelView(
        tts: TTSCoordinator(),
        chapters: [],
        currentReaderChapterIndex: 0,
        activeTTSChapterIndex: nil,
        activeChapterTitle: "",
        onPlayPause: {},
        onPreviousChapter: { false },
        onNextChapter: { false },
        onSelectChapter: { _ in },
        bookID: UUID(),
        detectedSpeakers: ["张若尘", "池瑶"],
        aiAdapter: AIBookContentAdapter(bookID: UUID(), chapters: [], textForChapter: { _ in nil }),
        aiProgress: 0.42
    )
}

// MARK: - TTS Control Panel

struct TTSPanelView: View {
    @ObservedObject var tts: TTSCoordinator
    let chapters: [BookChapter]
    let currentReaderChapterIndex: Int
    let activeTTSChapterIndex: Int?
    let activeChapterTitle: String
    let onPlayPause: () -> Void
    let onPreviousChapter: () -> Bool
    let onNextChapter: () -> Bool
    let onSelectChapter: (Int) -> Void
    let bookID: UUID
    /// Characters detected in the chapter being read, for 多角色朗讀. Computed by the
    /// reader, which is the only thing holding the chapter's narration text.
    let detectedSpeakers: [String]
    /// Passed through to 多角色朗讀 so character cards can be built where they are used.
    let aiAdapter: AIBookContentAdapter
    /// Reading position on the chunks' 0…1 scale, so the character list defaults to who has
    /// actually appeared.
    let aiProgress: Double
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var gs = GlobalSettings.shared
    @State private var isScrubbing = false
    @State private var scrubProgress = 0.0
    @State private var showChapterPicker = false

    // Playback is always available: when no HTTP source is configured, the coordinator falls
    // back to the on-device offline voice.
    private var hasAudioSource: Bool { true }

    private var usesSystemVoice: Bool {
        gs.ttsUseSystemVoice
            || gs.httpTtsUrlTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The system voice saturates at `AVSpeechUtteranceMaximumSpeechRate`, so say so
    /// instead of letting the upper half of the slider do nothing.
    private var systemVoiceRateIsCapped: Bool {
        usesSystemVoice && tts.speechRate > SystemTTSEngine.maxSupportedUIRate
    }

    private var controlChapterIndex: Int {
        activeTTSChapterIndex ?? currentReaderChapterIndex
    }

    private var canGoPreviousChapter: Bool {
        controlChapterIndex > 0
    }

    private var canGoNextChapter: Bool {
        controlChapterIndex < chapters.count - 1
    }

    private var playbackProgress: Double {
        guard tts.totalSegments > 1 else { return 0 }
        return Double(tts.currentSegmentIndex) / Double(tts.totalSegments - 1)
    }

    /// Speech rate as the percentage shown under the slider; also what VoiceOver reads
    /// as the slider's value, so it doesn't fall back to a raw fraction of the range.
    private var speechRateText: String {
        String(format: "%.0f%%", tts.speechRate / 0.5 * 100)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    if let notice = tts.playbackNotice {
                        noticeCard
                    }

                    playerCard
                    sourceCard
                    directoryCard
                    speedCard
                    sleepCard
                    playbackBehaviorCard
                    highlightCard
                }
                .padding(DSSpacing.lg)
            }
            .softScrollEdges()
            .scrollContentBackground(.hidden)
            .navigationTitle(localized("语音朗读"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label(localized("完成"), systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel(localized("完成"))
                }
            }
            .background(PageBackgroundView(scope: .settings).ignoresSafeArea())
            .pageBackgroundToolbar(for: .settings)
            .alert(
                localized("语音朗读"),
                isPresented: Binding(
                    get: { tts.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented { tts.dismissError() }
                    }
                )
            ) {
                Button(localized("好"), role: .cancel) { tts.dismissError() }
            } message: {
                Text(tts.errorMessage ?? "")
            }
            .sheet(isPresented: $showChapterPicker) {
                NavigationStack {
                    List(chapters.indices, id: \.self) { index in
                        Button {
                            showChapterPicker = false
                            onSelectChapter(index)
                        } label: {
                            HStack {
                                Text(chapters[index].title)
                                    .foregroundStyle(DSColor.textPrimary)
                                Spacer()
                                if index == controlChapterIndex {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(DSColor.appAccent)
                                }
                            }
                        }
                    }
                    .softScrollEdges()
                    .scrollContentBackground(.hidden)
                    .background(PageBackgroundView(scope: .settings).ignoresSafeArea())
                    .pageBackgroundToolbar(for: .settings)
                    .navigationTitle(localized("目录"))
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showChapterPicker = false
                            } label: {
                                Image(systemName: "xmark")
                            }
                        }
                    }
                }
            }
            .onChange(of: tts.currentSegmentIndex) { _, _ in
                if !isScrubbing {
                    scrubProgress = playbackProgress
                }
            }
            .onChange(of: gs.ttsKeepsScreenAwake) { _, _ in
                tts.updateScreenAwakePreference()
            }
        }
    }
}

// MARK: - TTS Highlight bindings + sleep label

private extension TTSPanelView {
    var sleepTimerLabel: String {
        tts.sleepMinutes == 0 ? localized("不定时") : "\(tts.sleepMinutes) \(localized("分鐘"))"
    }

    var ttsHighlightEnabledBinding: Binding<Bool> {
        Binding(get: { gs.ttsHighlightEnabled }, set: { gs.ttsHighlightEnabled = $0 })
    }

    var ttsHighlightColorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: GlobalSettings.uiColor(rgbHex: gs.ttsHighlightColorHex)) },
            set: { gs.ttsHighlightColorHex = UIColor($0).rgbHex ?? GlobalSettings.defaultTTSHighlightColorHex }
        )
    }

    var ttsHighlightBoxEnabledBinding: Binding<Bool> {
        Binding(get: { gs.ttsHighlightBoxEnabled }, set: { gs.ttsHighlightBoxEnabled = $0 })
    }

    var ttsHighlightBoxColorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: GlobalSettings.uiColor(rgbHex: gs.ttsHighlightBoxColorHex)) },
            set: { gs.ttsHighlightBoxColorHex = UIColor($0).rgbHex ?? GlobalSettings.defaultTTSHighlightBoxColorHex }
        )
    }

    var ttsHighlightBoxStyleBinding: Binding<Int> {
        Binding(get: { gs.ttsHighlightBoxStyleRaw }, set: { gs.ttsHighlightBoxStyleRaw = $0 })
    }
}

// MARK: - TTS Panel visual rebuild

private extension TTSPanelView {
    // A rounded, glass-capable card with consistent padding and a soft lift.
    func card<Content: View>(
        radius: CGFloat = DSRadius.xl,
        fill: Color = DSColor.surface,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .interfaceCardSurface(in: RoundedRectangle(cornerRadius: radius), fill: fill)
            .shadow(color: DSColor.shadow, radius: 10, y: 4)
    }

    var divider: some View {
        DSColor.separator
            .frame(height: 1)
            .padding(.vertical, DSSpacing.xxs)
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DSFont.callout)
            .foregroundStyle(DSColor.textSecondary)
    }

    func iconBadge(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(DSFont.fixed(size: 18, weight: .semibold))
            .foregroundStyle(DSColor.appAccent)
            .frame(width: 36, height: 36)
            .background(Circle().fill(DSColor.appAccentSoft))
    }

    // MARK: Notice

    var noticeCard: some View {
        card {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(DSColor.warning)
                    .accessibilityHidden(true)
                Text(tts.playbackNotice ?? "")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                Spacer(minLength: 0)
                Button {
                    tts.dismissPlaybackNotice()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("关闭提示"))
            }
        }
    }

    // MARK: Player (hero card)

    var playerCard: some View {
        card(radius: DSRadius.xxxl, fill: DSColor.appAccentSoft) {
            VStack(spacing: DSSpacing.lg) {
                VStack(spacing: DSSpacing.xs) {
                    if tts.playbackState != .stopped {
                        Label(localized("正在朗读"), systemImage: "waveform")
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.appAccent)
                            .accessibilityHidden(true)
                    }
                    Text(activeChapterTitle.isEmpty ? localized("尚未选择章节") : activeChapterTitle)
                        .font(DSFont.title3)
                        .foregroundStyle(DSColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if tts.playbackState != .stopped, tts.totalSegments > 0 {
                        Text("\(localized("章節進度")) \(tts.currentSegmentIndex + 1) / \(tts.totalSegments)")
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }

                HStack(spacing: DSSpacing.lg) {
                    Spacer()
                    previousChapterButton
                    playPauseButton
                    nextChapterButton
                    Spacer()
                }

                if tts.playbackState != .stopped, tts.totalSegments > 1 {
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        Slider(
                            value: Binding(
                                get: { isScrubbing ? scrubProgress : playbackProgress },
                                set: { scrubProgress = $0 }
                            ),
                            in: 0...1,
                            onEditingChanged: { editing in
                                isScrubbing = editing
                                if editing {
                                    scrubProgress = playbackProgress
                                } else {
                                    tts.seekToProgress(scrubProgress)
                                }
                            }
                        )
                        .tint(DSColor.appAccent)
                        HStack {
                            Text(localized("章节开始"))
                            Spacer()
                            Text(localized("章节结尾"))
                        }
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
        }
    }

    var previousChapterButton: some View {
        Button {
            ttsLog("[TTS][Panel] previousChapterButton tapped state=\(tts.playbackState) chapter=\(controlChapterIndex)")
            _ = onPreviousChapter()
        } label: {
            ZStack {
                Circle()
                    .fill(DSColor.surface)
                    .overlay(Circle().stroke(DSColor.separator, lineWidth: 1))
                Image(systemName: "backward.fill")
                    .font(DSFont.fixed(size: 20, weight: .medium))
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityHidden(true)
            }
            .frame(width: 56, height: 56)
        }
        .shadow(color: DSColor.shadow, radius: 6, y: 2)
        .disabled(!hasAudioSource || !canGoPreviousChapter)
    }

    var playPauseButton: some View {
        Button {
            ttsLog("[TTS][Panel] playButton tapped coordinatorPlaying=\(tts.isPlaying) state=\(tts.playbackState) chapter=\(controlChapterIndex)")
            if hasAudioSource {
                onPlayPause()
            } else {
                ttsLog("[TTS][Panel] ignored play tap because audio source is not configured")
            }
        } label: {
            ZStack {
                Circle().fill(DSColor.appAccent)
                Image(systemName: tts.playbackState == .playing ? "pause.fill" : "play.fill")
                    .font(DSFont.fixed(size: 30, weight: .semibold))
                    .foregroundStyle(DSColor.textOnAccent)
                    .accessibilityHidden(true)
            }
            .frame(width: 76, height: 76)
        }
        .shadow(color: DSColor.appAccent.opacity(0.35), radius: 12, y: 4)
        .accessibilityIdentifier("tts_panel_play_pause")
        .accessibilityLabel(localized(tts.playbackState == .playing ? "暂停" : "播放"))
        .disabled(tts.playbackState == .stopped && !hasAudioSource)
    }

    var nextChapterButton: some View {
        Button {
            ttsLog("[TTS][Panel] nextChapterButton tapped state=\(tts.playbackState) chapter=\(controlChapterIndex)")
            _ = onNextChapter()
        } label: {
            ZStack {
                Circle()
                    .fill(DSColor.surface)
                    .overlay(Circle().stroke(DSColor.separator, lineWidth: 1))
                Image(systemName: "forward.fill")
                    .font(DSFont.fixed(size: 20, weight: .medium))
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityHidden(true)
            }
            .frame(width: 56, height: 56)
        }
        .shadow(color: DSColor.shadow, radius: 6, y: 2)
        .disabled(!hasAudioSource || !canGoNextChapter)
    }

    // MARK: Source + multi-role

    var sourceCard: some View {
        card {
            VStack(spacing: 0) {
                sourceSettingsRow
                divider
                multiRoleRow
                if usesSystemVoice {
                    HStack(spacing: DSSpacing.sm) {
                        Image(systemName: "iphone.gen2")
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityHidden(true)
                        Text(localized("未配置网路语音源，将使用系统离线语音朗读"))
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, DSSpacing.md)
                }
            }
        }
    }

    var sourceSettingsRow: some View {
        NavigationLink(destination: TTSSettingsView()) {
            HStack(spacing: DSSpacing.md) {
                iconBadge("waveform")
                Text(localized("语音源设定"))
                    .font(DSFont.callout)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: DSSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var multiRoleRow: some View {
        NavigationLink {
            if aiAdapter.isPrepared {
                TTSRoleCastView(
                    bookID: bookID,
                    detectedSpeakers: detectedSpeakers,
                    adapter: aiAdapter,
                    progress: aiProgress
                )
            } else {
                ProgressView(localized("载入中…"))
            }
        } label: {
            HStack(spacing: DSSpacing.md) {
                iconBadge("person.2.wave.2")
                Text(localized("多角色朗读"))
                    .font(DSFont.callout)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: DSSpacing.sm)
                if gs.ttsMultiRoleEnabled {
                    Text(localized("开启"))
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.appAccent)
                }
                Image(systemName: "chevron.right")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Directory

    var directoryCard: some View {
        card {
            Button {
                showChapterPicker = true
            } label: {
                HStack(spacing: DSSpacing.md) {
                    iconBadge("list.bullet")
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(localized("目录"))
                            .font(DSFont.callout)
                            .foregroundStyle(DSColor.textPrimary)
                        Text(activeChapterTitle.isEmpty ? localized("未选择章节") : activeChapterTitle)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: DSSpacing.sm)
                    Image(systemName: "chevron.right")
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Speed

    var speedCard: some View {
        card {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                sectionHeader(localized("语速"))
                HStack {
                    Image(systemName: "tortoise")
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityHidden(true)
                    Slider(
                        value: Binding(
                            get: { tts.speechRate },
                            set: { tts.updateRate($0) }
                        ),
                        in: TTSCoordinator.minSpeechRate...TTSCoordinator.maxSpeechRate,
                        step: 0.05,
                        onEditingChanged: { editing in
                            if !editing { tts.applyRateToActivePlayback() }
                        }
                    )
                    .tint(DSColor.appAccent)
                    .accessibilityLabel(localized("语速"))
                    .accessibilityValue(speechRateText)
                    Image(systemName: "hare")
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityHidden(true)
                }
                Text("\(localized("當前速度"))：\(speechRateText)")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                if systemVoiceRateIsCapped {
                    Text(
                        String(
                            format: localized("系统语音最快 %@（iOS 限制），需要更快请改用网路语音"),
                            String(format: "%.0f%%", SystemTTSEngine.maxSupportedUIRate / 0.5 * 100)
                        )
                    )
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
    }

    // MARK: Sleep timer

    var sleepCard: some View {
        card {
            Menu {
                Button(localized("不定时")) { tts.setSleepTimer(minutes: 0) }
                ForEach([15, 30, 60, 90], id: \.self) { min in
                    Button("\(min) \(localized("分鐘"))") { tts.setSleepTimer(minutes: min) }
                }
            } label: {
                HStack(spacing: DSSpacing.md) {
                    iconBadge("moon.zzz")
                    Text(localized("定时停止"))
                        .font(DSFont.callout)
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer(minLength: DSSpacing.sm)
                    Text(sleepTimerLabel)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
        }
    }

    // MARK: Playback behavior

    var playbackBehaviorCard: some View {
        card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                sectionHeader(localized("播放行为"))
                Toggle(localized("朗读时保持萤幕开启"), isOn: $gs.ttsKeepsScreenAwake)
                Text(localized("只防止自动锁定，按下电源键仍可锁屏并继续朗读。"))
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    // MARK: Highlight

    var highlightCard: some View {
        card {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                sectionHeader(localized("高亮"))
                Toggle(localized("朗读高亮"), isOn: ttsHighlightEnabledBinding)

                if gs.ttsHighlightEnabled {
                    ColorPicker(
                        localized("高亮颜色"),
                        selection: ttsHighlightColorBinding,
                        supportsOpacity: false
                    )

                    Toggle(localized("朗读底色框"), isOn: ttsHighlightBoxEnabledBinding)

                    if gs.ttsHighlightBoxEnabled {
                        Picker(localized("底色框样式"), selection: ttsHighlightBoxStyleBinding) {
                            Text(localized("纯色块")).tag(0)
                            Text(localized("渐层胶囊")).tag(1)
                        }
                        .pickerStyle(.segmented)
                        .tint(DSColor.appAccent)

                        ColorPicker(
                            localized("底色框颜色"),
                            selection: ttsHighlightBoxColorBinding,
                            supportsOpacity: false
                        )
                    }
                }

                Text(localized("朗读时高亮目前正在念的文字。"))
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
    }
}
