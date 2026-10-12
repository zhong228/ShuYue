import CryptoKit
import Foundation

/// Disk cache for a source's parsed discover categories (`getExploreItems` output).
///
/// Mirrors Legado's `exploreKinds` cache: `@js:`-driven discover pages run a JS
/// (often with network requests) just to produce the category list, and that list
/// is stable for a given (source rule, discover runtime variables) pair. The key is
/// an MD5 over bookSourceUrl + exploreUrl + the discover-relevant runtime-variable
/// JSON, so editing the source's rule or switching a 發現頁 filter naturally maps to
/// a different entry — no explicit invalidation needed. Pull-to-refresh and the
/// toolbar refresh button bypass the cache and overwrite it (`forceRefresh`).
final class DiscoverKindsCache {
    static let shared = DiscoverKindsCache()

    private struct Entry: Codable {
        var items: [ModernParserBridge.DiscoverItem]
        var timestamp: Date
    }

    /// Freshness window for the parsed category list. The list is stable for a
    /// given (rule, discover variables) key, but the site still evolves; Legado's
    /// `exploreKinds` keeps far longer, yet a stale list surfaces as "发现页分类
    /// 一直是这样" with no way to notice — pull-to-refresh bypasses the cache, but
    /// cold-branding the entry for an hour is the same budget as `SearchResultCache`.
    private static let entryTTL: TimeInterval = 3600

    private let queue = DispatchQueue(label: "com.yuedu.discoverKindsCache")

    private lazy var directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiscoverKindsCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    func items(forKey key: String) -> [ModernParserBridge.DiscoverItem]? {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL(forKey: key)),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data),
                  !entry.items.isEmpty,
                  Date().timeIntervalSince(entry.timestamp) < Self.entryTTL
            else { return nil }
            return entry.items
        }
    }

    func store(_ items: [ModernParserBridge.DiscoverItem], forKey key: String) {
        guard !items.isEmpty else { return }
        let entry = Entry(items: items, timestamp: Date())
        queue.sync {
            guard let data = try? JSONEncoder().encode(entry) else { return }
            try? data.write(to: fileURL(forKey: key), options: .atomic)
        }
    }

    func removeAll() {
        queue.sync {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Stable cache key. `variableJSON` is the canonical JSON of the source's
    /// sanitized discover runtime variables (nil when the source has none).
    static func key(sourceUrl: String, exploreUrl: String, variableJSON: String?) -> String {
        var hasher = CryptoKit.Insecure.MD5()
        func feed(_ s: String) {
            let bytes = Array(s.utf8)
            hasher.update(data: Data(bytes))
        }
        feed(sourceUrl)
        feed("|")
        feed(exploreUrl)
        feed("|")
        feed(variableJSON ?? "")
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
