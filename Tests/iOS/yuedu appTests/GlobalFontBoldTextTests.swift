import Testing
import SwiftUI
import UIKit
@testable import yuedu_app

/// Bold Text reaches the global font (Apple HIG › Typography: a custom font has to do
/// what the system font does). SwiftUI bolds only its own fonts — a custom font drew
/// the same with `legibilityWeight` at `.bold` (measured 2026-09-29).
@Suite("Global font under Bold Text", .serialized)
@MainActor
struct GlobalFontBoldTextTests {
    /// HelveticaNeue ships with the system and has the heavier faces to step to.
    private let family = "HelveticaNeue"

    @Test("a custom font turns one step heavier while Bold Text is on")
    func customFontTurnsHeavier() {
        let saved = GlobalAppTypography.isBoldTextActive
        defer { GlobalAppTypography.isBoldTextActive = saved }

        GlobalAppTypography.isBoldTextActive = false
        let regular = Self.ink(of: GlobalAppTypography.font(.body, postScriptName: family))
        GlobalAppTypography.isBoldTextActive = true
        let bold = Self.ink(of: GlobalAppTypography.font(.body, postScriptName: family))
        #expect(bold > regular * 1.15, "regular \(regular), bold \(bold)")
    }

    @Test("the bar fonts take the bold face too")
    func barFontsTakeTheBoldFace() {
        let saved = GlobalAppTypography.isBoldTextActive
        defer { GlobalAppTypography.isBoldTextActive = saved }

        GlobalAppTypography.isBoldTextActive = false
        let regular = GlobalAppTypography.unscaledUIFont(.caption2, postScriptName: family)
        #expect(!regular.fontDescriptor.symbolicTraits.contains(.traitBold))
        GlobalAppTypography.isBoldTextActive = true
        let bold = GlobalAppTypography.unscaledUIFont(.caption2, postScriptName: family)
        #expect(bold.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    @Test("the system font is left to the system")
    func systemFontIsLeftAlone() {
        let saved = GlobalAppTypography.isBoldTextActive
        defer { GlobalAppTypography.isBoldTextActive = saved }

        GlobalAppTypography.isBoldTextActive = true
        #expect(GlobalAppTypography.font(.body, postScriptName: nil) == Font.body)
        #expect(GlobalAppTypography.font(.headline, postScriptName: nil) == Font.headline)
    }

    /// A font with no bold face has nothing to step to, and SwiftUI synthesizes none
    /// (measured with Chalkduster): while Bold Text is on it gives way to the system
    /// font, which turns bold by itself (user's call, 2026-09-29).
    @Test("a font with no bold face gives way to the system font under Bold Text")
    func singleWeightFontGivesWay() {
        #expect(GlobalAppTypography.hasBolderFace(family))
        #expect(!GlobalAppTypography.hasBolderFace("Chalkduster"))
        #expect(GlobalAppTypography.effectivePostScriptName("Chalkduster", boldText: true) == nil)
        #expect(GlobalAppTypography.effectivePostScriptName("Chalkduster", boldText: false) == "Chalkduster")
        #expect(GlobalAppTypography.effectivePostScriptName(family, boldText: true) == family)
        #expect(GlobalAppTypography.effectivePostScriptName(nil, boldText: true) == nil)
    }

    @Test("one step heavier, as the system font moves")
    func weightLadder() {
        #expect(GlobalAppTypography.boldTextWeight(Font.Weight.regular) == .semibold)
        #expect(GlobalAppTypography.boldTextWeight(Font.Weight.semibold) == .bold)
        #expect(GlobalAppTypography.boldTextWeight(Font.Weight.black) == .black)
        #expect(GlobalAppTypography.boldTextWeight(UIFont.Weight.regular) == .semibold)
        #expect(GlobalAppTypography.boldTextWeight(UIFont.Weight.medium) == .bold)
        #expect(GlobalAppTypography.boldTextWeight(UIFont.Weight.black) == .black)
    }

    /// Opacity summed over a rendering of sample text: more ink, heavier strokes.
    private static func ink(of font: Font) -> Double {
        let renderer = ImageRenderer(content: Text("MMM 永和").font(font).padding(2))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return 0 }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + Double(bytes[$1]) / 255 }
    }
}
