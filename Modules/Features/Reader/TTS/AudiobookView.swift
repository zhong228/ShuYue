import AVFoundation
import CoreImage
import SwiftUI

// MARK: - Audiobook Reader (dedicated full-screen player page)
//
// The reader for `.audio` books. `BookReaderView` routes here once a book is
// detected as an audiobook. Playback itself lives in the long-lived
// `AudiobookPlayer.shared` singleton, so dismissing this page keeps audio going
// with lock-screen controls; re-opening re-attaches to the live session.

struct AudiobookReaderView: View {
    let bookId: UUID

    @EnvironmentObject var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudiobookPlayer.shared

    @State private var sliderValue: Double = 0
    @State private var isDraggingSlider = false
    /// The chapter the slider is scrubbing; its position is only meaningful on that chapter.
    @State private var scrubbedChapter: Int?
    @State private var showChapterList = false
    @State private var showSleepTimer = false
    @State private var showSkipCredits = false
    @State private var baseColor: Color = DSColor.coverGradients[0][0]

    var body: some View {
        GeometryReader { geo in
            // 钉在安全区内：内容宽高 = 可用屏幕宽高，封面按「屏幕宽度 − 边距」与
            // 「可用高度的比例」取小来限高，杜绝封面按整屏宽度撑成正方形后整体
            // 顶出屏幕（底部播放键被挤出、功能行只露出几项）的溢出问题。
            let coverSize = min(geo.size.width - 104, geo.size.height * 0.46)
            ZStack {
                backgroundGradient(size: geo.size)

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: DSSpacing.sm)
                    coverArt(size: coverSize)
                    titleBlock
                        .padding(.horizontal, DSSpacing.xl)
                        .padding(.top, DSSpacing.lg)
                    if let message = player.error {
                        errorBlock(message)
                    }
                    functionRow
                        .padding(.top, DSSpacing.lg)
                    Spacer(minLength: DSSpacing.md)
                    progressSection
                    transportRow
                        .padding(.top, DSSpacing.sm)
                }
                .padding(.bottom, DSSpacing.lg)
                .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
            }
            // 钉死 ZStack 的布局尺寸：背景图 scaledToFill 会把布局撑得比屏幕宽
            // （竖版封面填满高度后宽度溢出），GeometryReader 又是顶左对齐摆放，
            // 内容就会被推向右侧偏离屏幕中心。显式 frame 后布局恒等于可用屏幕，
            // 背景图只负责「画」，不再参与撑大布局。
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // Dark styling for THIS page only. `.preferredColorScheme(.dark)` applies to the
        // whole window, which flipped the bookshelf dark for an instant during the
        // fullScreenCover transition (the "theme flashes black" bug). The environment
        // override scopes the dark appearance to this subtree; the page paints its own
        // dark gradient background, so nothing else is needed.
        .environment(\.colorScheme, .dark)
        .onAppear {
            if let book = store.readingBook(id: bookId) {
                player.start(book: book, store: store)
            } else if !player.isActive(bookId: bookId) {
                dismiss()
            }
            updateBaseColor()
        }
        .onChanged(of: player.bookId) { _ in updateBaseColor() }
        .onChanged(of: player.currentTime) { t in
            if !isDraggingSlider { sliderValue = t }
        }
        .sheet(isPresented: $showChapterList) {
            AudiobookChapterListView(player: player)
        }
        .sheet(isPresented: $showSleepTimer) {
            AudiobookSleepTimerView(player: player)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSkipCredits) {
            AudiobookSkipCreditsView(player: player)
                .presentationDetents([.medium])
        }
    }

    // MARK: Background

    /// 全屏封面模糊底（Apple Music 式）：封面放大虚化铺满，再压一层主色到黑的渐变，
    /// 让播放页由这本书自己的封面「发光」，而非一块通用黑底。
    /// `scaledToFill` 会按填充后的真实尺寸参与布局（竖版封面宽度会超出屏幕），
    /// 必须先用显式 frame 把布局尺寸约束到屏幕大小，模糊/放大只作为渲染溢出。
    private func backgroundGradient(size: CGSize) -> some View {
        ZStack {
            if let image = player.coverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 64, opaque: true)
                    .scaleEffect(1.4)
                    .opacity(0.45)
            }
            LinearGradient(
                // 底部必须不透明：半透明黑渐变会在收起动画中与下层页面混合，
                // 屏幕最底部闪出一块「黑色透明区域」。纯黑收尾则过渡无缝。
                colors: [baseColor.opacity(0.72), .black],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        // 背景下滑 = 收起播放页：手势落在空白处同样有效。
        .gesture(minimizeDrag)
    }

    private func updateBaseColor() {
        baseColor = Self.dominantColor(from: player.coverImage) ?? DSColor.coverGradients[0][0]
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(DSFont.fixed(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("收合"))
            Spacer()
            // 中间的章节索引「N / M」按反馈移除：顶部只保留收合按钮。
            Spacer()
            // Symmetry spacer matching the close button width.
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.sm)
    }

    // MARK: Cover

    /// 截图样式：接近全宽的大圆角封面，外面套一圈留缝的玻璃圆角框，
    /// 底部中央一枚播放均衡器。封面尺寸由调用方按屏幕宽高取小传入，保证不溢出。
    private func coverArt(size: CGFloat) -> some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay { coverContent.scaledToFill() }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                if player.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .overlay(alignment: .bottom) {
                coverEqualizer
                    .padding(.bottom, 14)
            }
            .background {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .padding(-10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .padding(-10)
            }
            .shadow(color: .black.opacity(0.4), radius: 26, x: 0, y: 14)
        // 封面/背景下滑 = 收起播放页回到迷你播放条：边听边逛其他页面。
        .gesture(minimizeDrag)
    }

    @ViewBuilder
    private var coverContent: some View {
        if let image = player.coverImage {
            Image(uiImage: image)
                .resizable()
        } else {
            ZStack {
                Rectangle().fill(.white.opacity(0.12))
                Image(systemName: "headphones")
                    .font(DSFont.fixed(size: 64))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    /// 封面底部的小均衡器：播放时波形逐格流动（系统 symbol 动效）。
    private var coverEqualizer: some View {
        Image(systemName: "waveform")
            .font(DSFont.fixed(size: 15, weight: .semibold))
            .symbolEffect(
                .variableColor.iterative,
                options: .repeating,
                isActive: player.isPlaying
            )
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35), in: Capsule())
            .accessibilityHidden(true)
    }

    // MARK: Title

    private var titleBlock: some View {
        // 截图样式：章节标题加粗左对齐，书名/作者一行小字在下。
        VStack(alignment: .leading, spacing: 6) {
            Text(player.currentChapterTitle.isEmpty ? player.bookTitle : player.currentChapterTitle)
                .font(DSFont.fixed(size: 22, weight: .bold, design: .serif))
                .foregroundColor(.white)
                .lineLimit(2)
            Text(player.bookTitle)
                .font(DSFont.fixed(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Function row

    /// 截图样式：封面下方一排五个功能位——模式 / 定时 / 倍速 / 音频列表 / 更多。
    private var functionRow: some View {
        HStack(spacing: 0) {
            Button { cyclePlayMode() } label: {
                // 文字随模式联动：顺序播放 / 单曲循环 / 随机播放 / 列表循环。
                functionLabel(icon: player.playMode.systemImage, text: player.playMode.localizedTitle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("播放模式"))
            .accessibilityValue(player.playMode.localizedTitle)

            Button { showSleepTimer = true } label: {
                functionLabel(icon: "timer", text: sleepLabel)
            }
            .buttonStyle(.plain)

            Menu {
                ForEach([Float(0.5), 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0], id: \.self) { rate in
                    Button {
                        player.setRate(rate)
                    } label: {
                        if player.playbackRate == rate {
                            Label(Self.rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(Self.rateLabel(rate))
                        }
                    }
                }
            } label: {
                functionLabel(icon: "speedometer", text: Self.rateLabel(player.playbackRate))
            }

            Button { showChapterList = true } label: {
                functionLabel(icon: "list.bullet", text: localized("音频列表"))
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    showSkipCredits = true
                } label: {
                    Label(localized("片頭片尾"), systemImage: skipsCredits ? "forward.fill" : "forward")
                }
            } label: {
                functionLabel(icon: "ellipsis", text: localized("更多"))
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private func functionLabel(icon: String, text: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(DSFont.fixed(size: 19, weight: .medium))
            Text(text)
                .font(DSFont.fixed(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.92))
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }

    /// 下滑收起：封面或背景上向下滑动即收起到迷你播放条，播放不中断。
    private var minimizeDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                if value.translation.height > 90, abs(value.translation.width) < 120 {
                    dismiss()
                }
            }
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(DSFont.caption)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Button(localized("重試")) {
                player.retryCurrentChapter()
            }
            .foregroundColor(.white)
            .font(DSFont.subheadline.weight(.semibold))
        }
        .padding(.horizontal, DSSpacing.xl)
        .padding(.top, DSSpacing.sm)
    }

    // MARK: Progress

    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: $sliderValue,
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        isDraggingSlider = true
                        scrubbedChapter = player.chapterIndex
                    } else if isDraggingSlider {
                        // Seek once per scrub. After a release at the far end the player
                        // received a seek to the current chapter's end every ~40 ms
                        // (simulator, CoreMedia log), and each one finished whichever
                        // chapter was current by then — chapters were skipped.
                        isDraggingSlider = false
                        player.seek(to: sliderValue, inChapter: scrubbedChapter)
                        scrubbedChapter = nil
                    }
                }
            )
            .tint(.white)
            .disabled(player.isLoading || player.duration <= 0)

            HStack {
                Text(Self.formatTime(sliderValue))
                Spacer()
                Text(Self.formatTime(player.duration))
            }
            .font(DSFont.fixed(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, DSSpacing.xl)
    }

    // MARK: Transport

    private var transportRow: some View {
        HStack(spacing: 0) {
            // 截图样式：±15 秒为无底圈的系统图标，主键为白色圆环。
            // 两端新增章节切换：上一章 / 下一章。
            Button { player.previousChapter() } label: {
                Image(systemName: "backward.end.fill")
                    .font(DSFont.fixed(size: 21, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 64)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(player.isLoading)
            .accessibilityLabel(localized("上一章"))
            Spacer()
            Button { player.skipBackward(15) } label: {
                Image(systemName: "gobackward.15")
                    .font(DSFont.fixed(size: 30, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("后退 15 秒"))
            Spacer()
            Button { player.togglePlayPause() } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                    Circle()
                        .stroke(Color.white, lineWidth: 2.5)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(DSFont.fixed(size: 34, weight: .semibold))
                        .foregroundColor(.white)
                        .offset(x: player.isPlaying ? 0 : 2)
                }
                .frame(width: 88, height: 88)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(player.isLoading)
            Spacer()
            Button { player.skipForward(15) } label: {
                Image(systemName: "goforward.15")
                    .font(DSFont.fixed(size: 30, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("前进 15 秒"))
            Spacer()
            Button { player.nextChapter() } label: {
                Image(systemName: "forward.end.fill")
                    .font(DSFont.fixed(size: 21, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 64)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(player.isLoading)
            .accessibilityLabel(localized("下一章"))
        }
        .padding(.horizontal, DSSpacing.xl)
    }

    // MARK: Bottom row

    private func cyclePlayMode() {
        player.cyclePlayMode()
        // The button's value changes under VoiceOver's focus without being read out.
        AccessibilityNotification.Announcement(player.playMode.localizedTitle).post()
    }

    private var skipsCredits: Bool {
        player.openingCreditsSeconds > 0 || player.closingCreditsSeconds > 0
    }

    private var sleepLabel: String {
        switch player.sleepOption {
        case .off: return localized("定時")
        case .endOfChapter: return localized("本章結束")
        case .minutes(let m): return "\(m)\(localized("分鐘"))"
        }
    }

    // MARK: Helpers

    static func rateLabel(_ rate: Float) -> String {
        if rate == rate.rounded() { return "\(Int(rate)).0x" }
        return "\(rate)x"
    }

    static func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Average color of the cover, used to tint the player background. Returns nil
    /// when there is no cover so callers can fall back to the palette.
    static func dominantColor(from image: UIImage?) -> Color? {
        guard let image, let cg = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cg)
        let extent = ciImage.extent
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: CIVector(cgRect: extent)]
        ), let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            output, toBitmap: &bitmap, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        // Darken slightly so white controls stay legible on pale covers.
        let scale = 0.82
        return Color(
            red: Double(bitmap[0]) / 255 * scale,
            green: Double(bitmap[1]) / 255 * scale,
            blue: Double(bitmap[2]) / 255 * scale
        )
    }
}

// MARK: - Chapter list

struct AudiobookChapterListView: View {
    @ObservedObject var player: AudiobookPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(player.chapters, id: \.index) { chapter in
                    Button {
                        player.selectChapter(chapter.index)
                        dismiss()
                    } label: {
                        HStack {
                            Text(chapter.title.isEmpty
                                 ? String(format: localized("第 %d 章"), chapter.index + 1)
                                 : chapter.title)
                                .foregroundStyle(DSColor.textPrimary)
                                .font(DSFont.subheadline)
                                .lineLimit(1)
                            Spacer()
                            if chapter.index == player.chapterIndex {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(DSColor.appAccent)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .interfaceSectionSurface()
                    .id(chapter.index)
                }
                .softScrollEdges()
                .onAppear { proxy.scrollTo(player.chapterIndex, anchor: .center) }
            }
            // Rows carry their own surface; the modifier below only clears the list
            // container, not each row's system fill. docs/design.md §4.1.
            .scrollContentBackground(.hidden)
            .background(PageBackgroundView(scope: .settings).ignoresSafeArea())
            .pageBackgroundToolbar(for: .settings)
            .navigationTitle(localized("目錄"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }
}

// MARK: - Sleep timer

struct AudiobookSleepTimerView: View {
    @ObservedObject var player: AudiobookPlayer
    @Environment(\.dismiss) private var dismiss

    private let minuteOptions = [10, 15, 20, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            List {
                option(localized("關閉"), isSelected: player.sleepOption == .off) {
                    player.setSleepOption(.off)
                }
                option(localized("本章結束"), isSelected: player.sleepOption == .endOfChapter) {
                    player.setSleepOption(.endOfChapter)
                }
                ForEach(minuteOptions, id: \.self) { m in
                    option("\(m) \(localized("分鐘"))", isSelected: player.sleepOption == .minutes(m)) {
                        player.setSleepOption(.minutes(m))
                    }
                }
            }
            .softScrollEdges()
            .scrollContentBackground(.hidden)
            .background(PageBackgroundView(scope: .settings).ignoresSafeArea())
            .pageBackgroundToolbar(for: .settings)
            .navigationTitle(localized("睡眠定時"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }

    private func option(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack {
                Text(title).foregroundStyle(DSColor.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundColor(DSColor.appAccent)
                }
            }
        }
        // Applied here rather than at each call site so every option row keeps the
        // shared surface instead of the opaque system default. docs/design.md §4.1.
        .interfaceSectionSurface()
    }
}

// MARK: - Skip credits

/// legado-E / legado-with-MD3 跳過片頭片尾: the seconds skipped at the start and cut at the
/// end of every chapter of this book, 0–180 each, in whole seconds as legado has them.
struct AudiobookSkipCreditsView: View {
    @ObservedObject var player: AudiobookPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var openingSeconds: Double
    @State private var closingSeconds: Double

    private let range = Double(AudiobookPlayer.creditsSecondsRange.lowerBound)
        ... Double(AudiobookPlayer.creditsSecondsRange.upperBound)

    init(player: AudiobookPlayer) {
        self.player = player
        _openingSeconds = State(initialValue: Double(player.openingCreditsSeconds))
        _closingSeconds = State(initialValue: Double(player.closingCreditsSeconds))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SettingsSliderRow(
                        title: localized("片頭"),
                        systemImage: "text.line.first.and.arrowtriangle.forward",
                        valueText: Self.secondsText(openingSeconds),
                        value: $openingSeconds,
                        range: range,
                        step: 1
                    )
                    SettingsSliderRow(
                        title: localized("片尾"),
                        systemImage: "text.line.last.and.arrowtriangle.forward",
                        valueText: Self.secondsText(closingSeconds),
                        value: $closingSeconds,
                        range: range,
                        step: 1
                    )
                } footer: {
                    Text(localized("只套用在這本書；片頭只在章節從頭播放時跳過。"))
                        .dsSectionFooter()
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .themedAppSurface(for: .settings)
            .navigationTitle(localized("跳過片頭片尾"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(localized("關閉"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        player.setSkipCredits(
                            openingSeconds: Int(openingSeconds.rounded()),
                            closingSeconds: Int(closingSeconds.rounded())
                        )
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(localized("完成"))
                }
            }
        }
    }

    private static func secondsText(_ seconds: Double) -> String {
        String(format: localized("%d 秒"), Int(seconds.rounded()))
    }
}

// MARK: - Play mode presentation

private extension AudiobookPlayMode {
    /// legado-with-MD3's names for the modes (`audio_play_mode_*`).
    var localizedTitle: String {
        switch self {
        case .listEndStop: return localized("順序播放")
        case .singleLoop: return localized("單曲循環")
        case .random: return localized("隨機播放")
        case .listLoop: return localized("列表循環")
        }
    }

    var systemImage: String {
        switch self {
        case .listEndStop: return "arrow.right.to.line"
        case .singleLoop: return "repeat.1"
        case .random: return "shuffle"
        case .listLoop: return "repeat"
        }
    }
}

#if DEBUG
#Preview {
    AudiobookReaderView(bookId: UUID())
        .environmentObject(BookStore())
}

#Preview("跳過片頭片尾") {
    AudiobookSkipCreditsView(player: .shared)
}
#endif
