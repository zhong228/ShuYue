import Foundation
import UIKit

/// A reading background the user made and named — a colour or a picture — kept in the
/// list beside 白色／護眼綠／棕色／黑色, choosable for either of the reader's modes under
/// 綁定閱讀主題 and synced through iCloud (2026-09-29). Before this there was one custom slot, and
/// making a new background overwrote the last one.
struct ReaderCustomBackground: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    /// The page colour. Under a picture it shows at the edges and while the picture loads.
    var colorHex: UInt32
    /// The picture, a file in the reading-backgrounds folder; nil for a plain colour.
    var imageFileName: String?
    /// The body text colour; nil takes whichever of dark or light text reads better.
    var textColorHex: UInt32?
    /// A dark background sits on 黑色, so the reader's chrome goes dark with it. It says
    /// nothing about which of the reader's modes wears it: a saved background is the
    /// light mode's, dark or not, unless 深色閱讀主題 picks it. Measured when the
    /// background is made — a picture by its average colour — since a picture cannot be
    /// measured on every page turn.
    var isDark: Bool
    /// iCloud merge clock: stamped on every local edit, never by a sync.
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: UInt32,
        imageFileName: String? = nil,
        textColorHex: UInt32? = nil,
        isDark: Bool,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.imageFileName = imageFileName
        self.textColorHex = textColorHex
        self.isDark = isDark
        self.updatedAt = updatedAt
    }

    /// The same two the single custom slot used before.
    static let darkTextHex: UInt32 = 0x2E322F
    static let lightTextHex: UInt32 = 0xF5F5F5

    var resolvedTextColorHex: UInt32 {
        textColorHex ?? (isDark ? Self.lightTextHex : Self.darkTextHex)
    }

    var isImage: Bool { imageFileName?.isEmpty == false }
}

/// The saved list as plain operations — `GlobalSettings` and the iCloud merge both go
/// through these, so the two cannot disagree about what an edit or a duplicate is.
enum ReaderCustomBackgroundLibrary {
    /// Every upsert is a local edit, so it stamps the merge clock: the edited background
    /// must outrank older copies of it on other devices.
    static func upserting(
        _ background: ReaderCustomBackground,
        into list: [ReaderCustomBackground],
        now: Date = Date()
    ) -> [ReaderCustomBackground] {
        var stamped = background
        stamped.updatedAt = now
        guard let index = list.firstIndex(where: { $0.id == background.id }) else {
            return list + [stamped]
        }
        var updated = list
        updated[index] = stamped
        return updated
    }

    static func deleting(id: UUID, from list: [ReaderCustomBackground]) -> [ReaderCustomBackground] {
        list.filter { $0.id != id }
    }

    static func uniqued(_ list: [ReaderCustomBackground]) -> [ReaderCustomBackground] {
        var seen = Set<UUID>()
        return list.filter { seen.insert($0.id).inserted }
    }

    /// `base`, or `base 2`, `base 3`… — the first one no saved background already uses.
    static func unusedName(base: String, among list: [ReaderCustomBackground]) -> String {
        let taken = Set(list.map(\.name))
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }
}

/// Whether a background is dark: light text reads better on it than dark text, by the
/// WCAG contrast ratio against the two text colours a saved background picks from.
enum ReaderBackgroundTone {
    static func isDark(rgbHex: UInt32) -> Bool {
        isDark(
            red: CGFloat((rgbHex >> 16) & 0xFF) / 255,
            green: CGFloat((rgbHex >> 8) & 0xFF) / 255,
            blue: CGFloat(rgbHex & 0xFF) / 255
        )
    }

    static func isDark(red: CGFloat, green: CGFloat, blue: CGFloat) -> Bool {
        let background = luminance(red: red, green: green, blue: blue)
        let dark = luminance(hex: ReaderCustomBackground.darkTextHex)
        let light = luminance(hex: ReaderCustomBackground.lightTextHex)
        let darkTextContrast = (background + 0.05) / (dark + 0.05)
        let lightTextContrast = (light + 0.05) / (background + 0.05)
        return lightTextContrast > darkTextContrast
    }

    /// A picture by its average colour.
    static func isDark(image: UIImage) -> Bool? {
        averageColorHex(image: image).map { isDark(rgbHex: $0) }
    }

    /// The colour a picture averages to — drawn into one pixel, which is what the eye
    /// averages it to from reading distance. Also the page colour under the picture.
    static func averageColorHex(image: UIImage) -> UInt32? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UInt32(pixel[0]) << 16 | UInt32(pixel[1]) << 8 | UInt32(pixel[2])
    }

    private static func luminance(hex: UInt32) -> CGFloat {
        luminance(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255
        )
    }

    private static func luminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
    }
}
