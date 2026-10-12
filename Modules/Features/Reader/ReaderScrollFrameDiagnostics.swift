import UIKit
import os

/// Timing evidence, not an FPS counter: adaptive display cadence and render/GPU
/// scheduling still require Instruments. Idle gaps never count as scroll gaps.
struct ReaderScrollFrameSample {
    let modelDelta: Double
    let presentationDelta: Double
    let updateDuration: Double
    let deadlineSlack: Double
    let offsetDelta: CGFloat
}

struct ReaderScrollFrameTimeline {
    private var previous: (model: Double, presentation: Double, offset: CGFloat)?

    mutating func sample(active: Bool, model: Double, presentation: Double,
                         started: Double, completed: Double, deadline: Double,
                         offset: CGFloat) -> ReaderScrollFrameSample? {
        guard active else { previous = nil; return nil }
        let old = previous
        previous = (model, presentation, offset)
        return ReaderScrollFrameSample(modelDelta: old.map { model - $0.model } ?? 0,
            presentationDelta: old.map { presentation - $0.presentation } ?? 0,
            updateDuration: max(0, completed - started), deadlineSlack: deadline - completed,
            offsetDelta: old.map { offset - $0.offset } ?? 0)
    }
}

@MainActor
final class ReaderScrollFrameDiagnostics {
    private static let signposter = OSSignposter(subsystem: Bundle.main.bundleIdentifier ?? "MoYue", category: "ReaderPerformance")
    private var link: AnyObject?
    private var started: Double?
    private var timeline = ReaderScrollFrameTimeline()

    init(scrollView: UIScrollView) {
        if #available(iOS 18.0, *) {
            let link = UIUpdateLink(view: scrollView)
            // Keep Apple's passive defaults: do not write frame scheduling
            // preferences (including requiresContinuousUpdates), request low
            // latency input or change the refresh-rate range.
            link.addAction(to: .afterUpdateScheduled) { [weak self] _, _ in
                guard Self.signposter.isEnabled else {
                    self?.started = nil
                    self?.timeline = ReaderScrollFrameTimeline()
                    return
                }
                self?.started = CACurrentMediaTime()
            }
            link.addAction(to: .afterUpdateComplete) { [weak self, weak scrollView] _, info in
                guard let self, let scrollView, let started = self.started else { return }
                self.started = nil
                let active = scrollView.isDragging || scrollView.isDecelerating
                guard let sample = self.timeline.sample(active: active, model: info.modelTime,
                    presentation: info.estimatedPresentationTime, started: started,
                    completed: CACurrentMediaTime(), deadline: info.completionDeadlineTime,
                    offset: scrollView.contentOffset.y) else { return }
                Self.signposter.emitEvent("viewport.frame",
                    "modelMs=\(sample.modelDelta * 1000) presentationMs=\(sample.presentationDelta * 1000) updateMs=\(sample.updateDuration * 1000) slackMs=\(sample.deadlineSlack * 1000) dy=\(sample.offsetDelta) y=\(scrollView.contentOffset.y) drag=\(scrollView.isDragging) decel=\(scrollView.isDecelerating)")
            }
            link.isEnabled = true
            self.link = link
        }
    }
}
