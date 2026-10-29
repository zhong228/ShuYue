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

    /// 书悦「暖书卷」冷启动字标：暖纸米底 + 朱砂红衬线字标。
    private var brandSplash: some View {
        ZStack {
            (colorScheme == .dark ? DSColor.inkBackgroundDark : DSColor.paperBackgroundLight)
                .ignoresSafeArea()
            VStack(spacing: DSSpacing.md) {
                Text(localized("书悦"))
                    .font(.system(size: 56, weight: .bold, design: .serif))
                    .foregroundStyle(DSColor.appAccent)
                    .accessibilityHidden(true)
                Text("SHUYUE")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(DSColor.appAccent.opacity(0.55))
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
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
