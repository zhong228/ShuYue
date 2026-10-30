import SwiftUI

/// A search's progress and its pause control, laid out as the 检索 page's
/// workbench draws it: the ring fills as the sources answer, beside it the
/// source currently being asked and how many have answered, failed, timed out
/// or were skipped — 「正在检索「阅读源」/ 18/27 · 失敗 4」— and beneath them
/// the pause / resume capsule, always visible while a search runs or is paused.
///
/// The workbench keeps this block above the results so the reader can stop or
/// carry on a long fan-out without hunting for a control.
struct SearchProgressControl: View {
    let progress: SearchAggregator.SearchProgress
    /// The source being asked right now, from the aggregator; `nil` while idle.
    let currentSourceName: String?
    let isPaused: Bool
    let onPause: () -> Void
    let onResume: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            HStack(alignment: .center, spacing: DSSpacing.md) {
                SearchProgressRing(fraction: progress.fraction, isPaused: isPaused)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    statusText
                    summary
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            pauseButton
        }
        .padding(DSSpacing.md)
        .background(
            DSColor.surface,
            in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .stroke(DSColor.border.opacity(0.6), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusText: some View {
        if isPaused {
            Text(localized("已暂停"))
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
        } else if let currentSourceName {
            Text(String(format: localized("正在检索「%@」"), currentSourceName))
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
        } else {
            Text(localized("搜索中…"))
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
        }
    }

    private var summary: some View {
        var text = Text("\(progress.completed)/\(progress.total)")
        if progress.timedOut > 0 {
            text = text + Self.separator
                + Text(String(format: localized("超时 %d"), progress.timedOut))
                    .foregroundStyle(DSColor.warning)
        }
        if progress.failed > 0 {
            text = text + Self.separator
                + Text(String(format: localized("失败 %d"), progress.failed))
                    .foregroundStyle(DSColor.destructive)
        }
        if progress.skipped > 0 {
            text = text + Self.separator
                + Text(String(format: localized("暂跳 %d"), progress.skipped))
        }
        return text
            .font(DSFont.footnote)
            .monospacedDigit()
            .foregroundStyle(DSColor.textSecondary)
            .lineLimit(1)
            .accessibilityHidden(true)
    }

    /// The one control of the block: pause an in-flight search, resume the
    /// sources not yet asked. Auto-pause lands in the same paused state, so the
    /// same capsule resumes an automatically paused search.
    private var pauseButton: some View {
        Button(action: isPaused ? onResume : onPause) {
            Label(
                isPaused ? localized("继续搜索") : localized("暂停搜索"),
                systemImage: isPaused ? "play.fill" : "pause.fill"
            )
            .font(DSFont.subheadline.weight(.semibold))
            .foregroundStyle(DSColor.appAccent)
            .frame(maxWidth: .infinity, minHeight: DSLayout.minimumTapTarget)
            .background(DSColor.appAccentSoft, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isPaused ? localized("继续搜索") : localized("暂停搜索"))
        .accessibilityValue(progress.total > 0 ? "\(progress.completed)/\(progress.total)" : "")
    }

    private static let separator = Text(" · ")
}

/// The ring itself: a grey track, the answered share drawn over it in the accent
/// colour, and the glyph for what a tap of the block does next.
private struct SearchProgressRing: View {
    let fraction: Double
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(DSColor.neutralControlFill, lineWidth: DSLayout.searchProgressRingLineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(
                    DSColor.accent,
                    style: StrokeStyle(lineWidth: DSLayout.searchProgressRingLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(DSFont.fixed(size: DSLayout.searchProgressRingGlyphSize, weight: .bold))
                .foregroundStyle(DSColor.accent)
                .accessibilityHidden(true)
        }
        .frame(width: DSLayout.searchProgressRingSize, height: DSLayout.searchProgressRingSize)
        // The arc follows each answer smoothly; with Reduce Motion it steps.
        .animation(reduceMotion ? nil : DSAnimation.standard, value: fraction)
        .accessibilityHidden(true)
    }
}

#Preview("检索进度") {
    VStack(spacing: DSSpacing.lg) {
        SearchProgressControl(
            progress: SearchAggregator.SearchProgress(total: 27, completed: 18, failed: 4),
            currentSourceName: "示例书源",
            isPaused: false,
            onPause: {},
            onResume: {}
        )
        SearchProgressControl(
            progress: SearchAggregator.SearchProgress(total: 27, completed: 9, timedOut: 2),
            currentSourceName: nil,
            isPaused: true,
            onPause: {},
            onResume: {}
        )
    }
    .padding()
    .background(DSColor.surfaceTertiary)
}