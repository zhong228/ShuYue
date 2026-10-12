@testable import YueduCoreText
import Testing
import UIKit
@testable import yuedu_app

@Suite(.serialized)
@MainActor
struct BrowserFragmentSubmissionTests {
    @Test func measureLoadedContentSubmissionAcrossOldTileBoundaries() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let viewport = CGSize(width: 392, height: 810)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let scroll = UIScrollView(frame: CGRect(origin: .zero, size: viewport))
        scroll.backgroundColor = .white
        root.view.addSubview(scroll)
        let config = BrowserLayoutConfig(renderWidth: viewport.width, renderHeight: viewport.height, rootFontSize: 22)
        let html = "<body>" + String(repeating: "<p>" + String(repeating: "春眠不覺曉，處處聞啼鳥。", count: 8) + "</p>", count: 30) + "</body>"
        let session = try HTMLLayoutDocument(html: html, configuration: config).makeViewportSession()
        let document = try session.layout(in: CGRect(x: 0, y: 0, width: viewport.width, height: 5000))
        let chapter = BrowserScrollChapter(spineIndex: 0, document: document, backgroundColor: .white, usesReaderBackground: false)
        scroll.contentSize = document.contentSize
        var times: [Bool: [Double]] = [:]
        var peakGlyphBatches: [Bool: Int] = [:]
        var peaks: [Bool: Int] = [:]
        // Alternate order: simulator caches must not always favour the new path.
        for fragments in [false, true, true, false] {
            let host = ReaderViewportFragmentHost(frame: CGRect(origin: .zero, size: document.contentSize))
            if fragments { scroll.addSubview(host) }
            var tiles: [Int: BrowserLayoutPageView] = [:]
            var previousCreates = 0
            func display(_ layer: CALayer) {
                layer.displayIfNeeded()
                layer.sublayers?.forEach(display)
            }
            func step(_ y: CGFloat, measuring: Bool) {
                autoreleasepool {
                    let start = SourcePerfTrace.now
                    scroll.contentOffset = CGPoint(x: 0, y: y)
                    var glyphCount = 0
                    if fragments {
                        host.update([.init(chapter: chapter, origin: .zero, width: viewport.width)],
                                    viewport: scroll.bounds, scale: window.screen.scale)
                        glyphCount = host.createdCount - previousCreates
                        previousCreates = host.createdCount
                        display(host.layer)
                        peaks[true] = max(peaks[true] ?? 0, host.estimatedBackingBytes)
                    } else {
                        let first = Int(y / viewport.height)
                        let last = Int((y + viewport.height - 1) / viewport.height)
                        for index in first...last where tiles[index] == nil {
                            let rect = CGRect(x: 0, y: CGFloat(index) * viewport.height,
                                              width: viewport.width, height: viewport.height)
                            let page = BrowserLayoutPageView(frame: rect)
                            page.usesContinuousScrolling = true
                            page.layer.drawsAsynchronously = true
                            page.displayList = document.items(in: rect.insetBy(dx: 0, dy: -1))
                            glyphCount += page.displayList.items.filter { if case .text = $0 { return true }; return false }.count
                            scroll.addSubview(page)
                            tiles[index] = page
                            page.setNeedsDisplay()
                            page.layer.displayIfNeeded()
                        }
                        for key in Array(tiles.keys) where key < first - 1 || key > last + 1 {
                            tiles.removeValue(forKey: key)?.removeFromSuperview()
                        }
                    }
                    CATransaction.flush()
                    if measuring {
                        let elapsed = (SourcePerfTrace.now - start) * 1000
                        times[fragments, default: []].append(elapsed)
                        peakGlyphBatches[fragments] = max(peakGlyphBatches[fragments] ?? 0, glyphCount)
                    }
                }
            }
            step(900, measuring: false)
            let batchStart = SourcePerfTrace.now
            for y in stride(from: CGFloat(912), through: 2808, by: 12) { step(y, measuring: true) }
            for y in stride(from: CGFloat(2796), through: 912, by: -12) { step(y, measuring: true) }
            SourcePerfTrace.record("test.fragment.submission", "fragments=\(fragments) steps=317", since: batchStart, thresholdMs: 0)
            host.removeFromSuperview()
            tiles.values.forEach { $0.removeFromSuperview() }
        }
        for mode in [false, true] {
            let samples = try #require(times[mode]).sorted()
            print("[FragmentSubmission] fragments=\(mode) samples=\(samples.count) medianMs=\(samples[samples.count / 2]) p95Ms=\(samples[Int(Double(samples.count - 1) * 0.95)]) maxMs=\(samples.last!) peakNewGlyphUnits=\(peakGlyphBatches[mode] ?? 0) peakBackingEstimate=\(peaks[mode] ?? 0)")
        }
        #expect(try #require(peakGlyphBatches[true]) < #require(peakGlyphBatches[false]),
                "content surfaces must spread preparation across lines instead of whole screens")
        #expect(try #require(peaks[true]) < ReaderViewportFragmentHost.retainedByteLimit)
        // These are simulator main-thread submission timings, not frame rate,
        // GPU duration, memory RSS, or proof that device hitches are eliminated.
    }
}
