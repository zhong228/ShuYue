import UIKit

/// Reuses font resolution within one prepared document. CSS/fonts have already
/// been registered before its resolver is created. A new document gets a new
/// resolver, so missing fonts and changed publication aliases cannot leak across
/// chapters or settings generations.
///
/// Continuous layout runs off the main thread, so one document's resolver may be
/// called from its layout thread and the main thread. The lock covers the cache
/// and the resolution itself: each tuple still resolves exactly once.
final class BrowserDocumentFontResolver: @unchecked Sendable {
    private struct Key: Hashable {
        let families: [String]
        let weight: Int
        let italic: Bool
        let size: CGFloat
    }

    private struct Resolution {
        let font: UIFont?
    }

    private let lock = NSLock()
    private let resolveFont: ([String], Int, Bool, CGFloat) -> UIFont?
    private let capacity: Int
    private var resolutions: [Key: Resolution] = [:]
    private var requests = 0
    private var resolved = 0
    var requestCount: Int { lock.withLock { requests } }
    var resolutionCount: Int { lock.withLock { resolved } }
    var retainedCount: Int { lock.withLock { resolutions.count } }

    init(capacity: Int = 128, resolve: @escaping ([String], Int, Bool, CGFloat) -> UIFont?) {
        self.capacity = max(0, capacity)
        self.resolveFont = resolve
    }

    func resolve(families: [String], weight: Int, italic: Bool, size: CGFloat) -> UIFont? {
        lock.withLock {
            requests += 1
            let key = Key(families: families, weight: weight, italic: italic, size: size)
            if let cached = resolutions[key] { return cached.font }
            resolved += 1
            let font = resolveFont(families, weight, italic, size)
            // Keep the original resolver as the only font-selection path. Unusual
            // documents exceeding the bound still resolve normally without retaining
            // more entries or evicting/rebuilding the frequently used first entries.
            if resolutions.count < capacity {
                resolutions[key] = Resolution(font: font)
            }
            return font
        }
    }
}
