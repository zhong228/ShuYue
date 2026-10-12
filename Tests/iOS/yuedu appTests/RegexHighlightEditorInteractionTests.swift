import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

@Suite("Regex highlight editor interactions", .serialized)
@MainActor
struct RegexHighlightEditorInteractionTests {
    @Test("imported fill image moves through real sliders while text stays anchored")
    func importedFillImageSliders() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/RegexHighlight/reader-settings.yuedustyle")
        let root = try readerStyleTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReaderStyleAssetStore(rootURL: root)
        let payload = try await ReaderStylePackage.import(Data(contentsOf: fixture), assetStore: store)
        let plan = try ReaderSettingsImportService.plan(from: payload)
        let configuration = try #require(plan.regexHighlights)
        let rule = try #require(configuration.rules.first { $0.id == "builtin.curly-double" })
        #expect(rule.lightStyle.decoration.backgroundImage?.contentMode == .fill)
        #expect(rule.lightStyle.decoration.backgroundImageOffsetX == nil)
        #expect(rule.lightStyle.decoration.backgroundImageOffsetY == nil)
        await store.prewarmRegexHighlightAssets(configuration: configuration, appearance: .light)

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 440, height: 1800)
        let host = UIHostingController(rootView: NavigationStack {
            RegexHighlightRuleEditorView(rule: rule) { _ in }
        })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        host.view.layoutIfNeeded()
        let tabs = try #require(await find(in: host.view) { view -> UISegmentedControl? in
            guard let segmented = view as? UISegmentedControl, segmented.numberOfSegments == 4 else { return nil }
            return segmented
        })
        tabs.selectedSegmentIndex = 1
        tabs.sendActions(for: .valueChanged)
        // SwiftUI owns the accessibility elements instead of forwarding labels
        // to UISlider. The two signed offset sliders start at their midpoint;
        // the collapsed crop controls are not materialized.
        let offsets = try #require(await find(in: host.view) { view -> [UISlider]? in
            guard view === host.view else { return nil }
            let sliders = descendants(view).compactMap { $0 as? UISlider }.filter {
                abs($0.value - ($0.minimumValue + $0.maximumValue) / 2) < 0.001
            }
            return sliders.count == 2 ? sliders : nil
        })
        let preview = try #require(await find(in: host.view) { $0 as? RegexHighlightLivePreviewView })
        let initial = try paintedBounds(preview)
        try savePreview(preview, name: "before")

        for (x, y) in [(24.0, 0.0), (24.0, 24.0), (-24.0, -24.0)] {
            for (slider, value) in zip(offsets, [x, y]) {
                slider.value = slider.minimumValue + Float((value + 48) / 96) * (slider.maximumValue - slider.minimumValue)
                slider.sendActions(for: .valueChanged)
            }
            let updated = await find(in: host.view) { view -> RegexHighlightLivePreviewView? in
                guard let view = view as? RegexHighlightLivePreviewView,
                      let decoration = try? decoration(in: view),
                      (decoration.style.backgroundImageOffsetX ?? 0) == x,
                      (decoration.style.backgroundImageOffsetY ?? 0) == y else { return nil }
                return view
            }
            let current = try #require(updated, "Native sliders must propagate both offsets to the preview")
            let moved = try paintedBounds(current)
            #expect(abs(moved.image.minX - initial.image.minX - x) <= 1)
            #expect(abs(moved.image.minY - initial.image.minY - y) <= 1)
            #expect(abs(moved.image.width - initial.image.width) <= 1)
            #expect(abs(moved.image.height - initial.image.height) <= 1)
            expectSameTextBounds(moved.text, initial.text)
            #expect(try decoration(in: current).style.backgroundImage == rule.lightStyle.decoration.backgroundImage,
                    "Moving the image must preserve its imported crop focus")
            try savePreview(current, name: "x\(Int(x))-y\(Int(y))")
        }
    }

    @Test("moving a later line's image upwards cannot cover earlier text")
    func imageStaysBehindEarlierText() throws {
        let id = UUID()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 420, height: 62), format: format).image { context in
            UIColor(red: 1, green: 0.8, blue: 0.5, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 420, height: 62))
        }
        ReaderStyleAssetImageCache.shared.insert(image, for: id)
        defer { ReaderStyleAssetImageCache.shared.remove(id) }
        let model = RegexHighlightRuleEditorModel(
            rule: .custom(name: "Image", pattern: "(?<=\\n)AAAA"), testText: "AAAA\nAAAA"
        ) { _ in }
        model.lightStyle.decoration.backgroundImage = .init(assetID: id)
        let view = RegexHighlightLivePreviewView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        view.contentInset = 52
        view.attributed = try model.previewAttributedString(appearance: .light, baseTextColor: .black)
        let initial = try paintedBounds(view)
        model.lightStyle.decoration.backgroundImageOffsetY = -20
        view.attributed = try model.previewAttributedString(appearance: .light, baseTextColor: .black)
        let moved = try paintedBounds(view)
        expectSameTextBounds(moved.text, initial.text)
        #expect(abs(moved.image.minY - initial.image.minY + 20) <= 1)
    }

    @Test("shifted images keep all pixels at scroll partition boundaries")
    func shiftedImagesSurviveScrollPartitions() throws {
        let id = UUID()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: 420, height: 62), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 420, height: 62))
        }
        ReaderStyleAssetImageCache.shared.insert(image, for: id)
        defer { ReaderStyleAssetImageCache.shared.remove(id) }
        for offsetY in [-48.0, 48.0] {
            var rule = RegexHighlightRule.custom(name: "Image", pattern: "AAAA")
            rule.lightStyle.decoration = .init(backgroundImage: .init(assetID: id),
                                               backgroundImageOffsetX: 17, backgroundImageOffsetY: offsetY)
            let attributed = NSMutableAttributedString(
                string: Array(repeating: "AAAA next line", count: 40).joined(separator: "\n"),
                attributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black]
            )
            _ = try RegexHighlightEngine.apply(
                configuration: .init(isEnabled: true, rules: [], customRules: [rule]),
                appearance: .light, to: attributed
            )
            let chunk = try #require(CoreTextChunkSlicer.slice(
                attributedString: attributed, chapterIndex: 0, contentWidth: 320
            ).chunks.first)
            chunk.materializeFrameIfNeeded()
            let bounds = CGRect(x: 0, y: 0, width: chunk.width, height: chunk.height)
            let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
            let reference = renderer.image { _ in CoreTextChunkDrawView.draw(chunk, bounds: bounds) }
            let fragments = CoreTextPaintFragment.make(chunk: chunk, scale: 1)
            #expect(fragments.count > 2)
            let actual = renderer.image { context in
                for fragment in fragments {
                    context.cgContext.saveGState()
                    context.cgContext.clip(to: fragment.rect)
                    CoreTextChunkDrawView.draw(chunk, bounds: bounds, lineIndices: fragment.lineIndices)
                    context.cgContext.restoreGState()
                }
            }
            #expect(reference.pngData() == actual.pngData(), "Translated backgrounds must remain intact across scroll fragments")
        }
    }

    private func expectSameTextBounds(_ actual: CGRect, _ expected: CGRect) {
        // Antialiased edge pixels change classification when a coloured image
        // moves behind them; a one-pixel tolerance still catches a moved or covered line.
        #expect(abs(actual.minX - expected.minX) <= 1)
        #expect(abs(actual.minY - expected.minY) <= 1)
        #expect(abs(actual.maxX - expected.maxX) <= 1)
        #expect(abs(actual.maxY - expected.maxY) <= 1)
    }

    private func decoration(in view: RegexHighlightLivePreviewView) throws -> RegexHighlightDecoration {
        try #require(view.attributed.attribute(RegexHighlightDecoration.attributeKey, at: 0, effectiveRange: nil) as? RegexHighlightDecoration)
    }

    private func find<T>(in root: UIView, matching: (UIView) -> T?) async -> T? {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            root.layoutIfNeeded()
            if let found = descendants(root).compactMap(matching).first { return found }
            await Task.yield()
        } while Date() < deadline
        return nil
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func render(_ view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    private func savePreview(_ view: UIView, name: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("regex-offset-\(name).png")
        try render(view).pngData()?.write(to: url)
        print("OFFSET PREVIEW", url.path)
    }

    private func paintedBounds(_ view: UIView) throws -> (image: CGRect, text: CGRect) {
        let image = try #require(render(view).cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var imageBounds = CGRect.null, textBounds = CGRect.null
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard pixels[i + 3] > 200 else { continue }
                let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                if pixels[i] > 200, pixels[i + 1] > 100, pixels[i + 2] < 230 {
                    imageBounds = imageBounds.union(pixel)
                } else if pixels[i] < 80, pixels[i + 1] < 80, pixels[i + 2] < 80 {
                    textBounds = textBounds.union(pixel)
                }
            }
        }
        #expect(!imageBounds.isNull)
        #expect(!textBounds.isNull)
        return (imageBounds, textBounds)
    }
}
