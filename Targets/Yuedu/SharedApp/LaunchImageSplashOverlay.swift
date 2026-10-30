import SwiftUI

/// Cold-launch splash overlay. iOS's real LaunchScreen can't be swapped at
/// runtime, so this paints the user's chosen image over the app root for a
/// moment on the first appearance, then fades out. Presents only when the
/// feature is enabled, Pro is active, and a matching image exists.
struct LaunchImageSplashOverlay: View {
    @ObservedObject private var settings = GlobalSettings.shared
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = true
    /// 品牌字标入场动画是否已播放（一次 spring 上浮淡入）。
    @State private var appeared = false

    /// Latches after the first appearance so returning from the background or a
    /// theme change never replays the splash.
    private static var hasPlayed = false

    private let holdDuration: UInt64 = 1_300_000_000  // 1.3s before fading
    private let minimalHoldDuration: UInt64 = 400_000_000  // 0.4s for non-Pro orphaned image

    /// Max time we wait at cold launch for StoreKit / Firestore entitlements to
    /// resolve before giving up on the splash. Defends against the race where
    /// `SubscriptionStore.refreshEntitlements()` (async, kicked off in
    /// `SubscriptionStore.init`) hasn't finished by the time ContentView's
    /// overlay first appears — without this wait, `isProActive` is still false,
    /// `currentImage` returns nil, the splash dismisses, and `hasPlayed` latches
    /// so the user's enabled splash never shows even though they are Pro.
    /// Can be deleted once entitlements load synchronously at app start.
    private let entitlementWaitNanoseconds: UInt64 = 1_500_000_000  // 1.5s

    var body: some View {
        ZStack {
            if visible {
                if let image = currentImage {
                    splash(image)
                        .transition(.opacity)
                } else {
                    // 书悦品牌冷启动字标：无自定义启动图时默认展示，
                    // 让打开 App 的第一屏与墨悦明显不同。
                    brandSplash
                        .transition(.opacity)
                }
            }
        }
        .animation(DSAnimation.splashFade, value: visible)
        .task {
            guard !Self.hasPlayed else {
                visible = false
                return
            }
            Self.hasPlayed = true

            // Wait for the entitlement gate to settle so we know whether to
            // hold the splash or dismiss fast. The image (if any) is already
            // visible from frame 1 because `currentImage` no longer gates on
            // entitlements — this wait only controls dismissal timing.
            if !subscriptionStore.isProActive {
                let deadline = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
                    + entitlementWaitNanoseconds
                while !subscriptionStore.isProActive {
                    if Task.isCancelled { return }
                    if UInt64(Date().timeIntervalSince1970 * 1_000_000_000) >= deadline {
                        break
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }

            // 品牌字标对所有人展示一次（非 Pro 也短暂显示后快速淡出），
            // 自定义启动图仍按原先 Pro 权限控制停留时长。
            if subscriptionStore.hasAccess(.launchScreen) {
                try? await Task.sleep(nanoseconds: holdDuration)
            } else {
                try? await Task.sleep(nanoseconds: minimalHoldDuration)
            }
            visible = false
        }
    }

    private func splash(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .background(colorScheme == .dark ? Color.black : Color.white)
        }
        .ignoresSafeArea()
    }

    /// 书悦「暖书卷」冷启动字标：暖纸米底 + 朱砂印章 + 衬线字标 +
    /// 底部墨色流动进度条。入场做一次上浮淡入，进度条为不确定态来回扫动，
    /// 与 1.3s 的停留时长同步。
    private var brandSplash: some View {
        ZStack {
            (colorScheme == .dark ? DSColor.inkBackgroundDark : DSColor.paperBackgroundLight)
                .ignoresSafeArea()
            // 顶部暖光晕：给纯色底一点纵深感，暗色下更明显。
            RadialGradient(
                colors: [
                    DSColor.appAccent.opacity(colorScheme == .dark ? 0.22 : 0.12),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.18),
                startRadius: 10,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                sealBadge
                    .padding(.bottom, DSSpacing.lg)
                Text(localized("书悦"))
                    .font(.system(size: 62, weight: .bold, design: .serif))
                    .tracking(10)
                    .foregroundStyle(DSColor.appAccent)
                    .accessibilityHidden(true)
                latinMark
                    .padding(.top, DSSpacing.sm)
                Spacer()
                loadingBar
                    .padding(.bottom, colorScheme == .dark ? 88 : 72)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !appeared else { return }
            withAnimation(.spring(response: 0.75, dampingFraction: 0.85).delay(0.05)) {
                appeared = true
            }
            // 不确定态进度条：滑块在轨道内来回扫。延迟到字标落定后启动。
            withAnimation(
                .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
                    .delay(0.45)
            ) {
                loadingShift = loadingRange
            }
        }
    }

    /// 朱砂印章：圆角方形印面 + 内描边 + 白文「悦」。
    private var sealBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(DSColor.appAccent)
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(DSColor.appAccentSoft.opacity(0.55), lineWidth: 1)
                .padding(4)
            Text(localized("悦"))
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(Color.white.opacity(0.96))
        }
        .frame(width: 68, height: 68)
        .shadow(color: DSColor.appAccent.opacity(0.28), radius: 18, x: 0, y: 8)
        .accessibilityHidden(true)
    }

    /// 「SHUYUE」拉丁字标，两侧发丝线收束视线。
    private var latinMark: some View {
        HStack(spacing: 10) {
            hairline
            Text("SHUYUE")
                .font(.system(size: 13, weight: .medium, design: .serif))
                .tracking(7)
                .foregroundStyle(DSColor.appAccent.opacity(0.55))
            hairline
        }
        .accessibilityHidden(true)
    }

    private var hairline: some View {
        Rectangle()
            .fill(DSColor.appAccent.opacity(0.28))
            .frame(width: 34, height: 1)
    }

    // MARK: Loading bar

    /// 轨道宽 168、滑块宽 64 → 单侧行程 52。
    private var loadingRange: CGFloat { 52 }

    @State private var loadingShift: CGFloat = -52

    private var loadingBar: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(DSColor.appAccent.opacity(0.14))
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            DSColor.appAccent.opacity(0.25),
                            DSColor.appAccent
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 64)
                .offset(x: loadingShift + 52)
        }
        .frame(width: 168, height: 4)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var currentImage: UIImage? {
        guard settings.launchImageEnabled,
              let url = settings.launchImageURL(for: colorScheme),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return image
    }
}

#Preview {
    LaunchImageSplashOverlay()
        .environmentObject(SubscriptionStore.shared)
}
