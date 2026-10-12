import Combine
import Foundation

// MARK: - Browser bookmarks

struct BrowserBookmark: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: String
    var createdAt: Date

    var host: String { URL(string: url)?.host ?? "" }

    /// Best-effort site icon, the same guess 最近瀏覽 makes.
    var faviconURL: URL? {
        host.isEmpty ? nil : URL(string: "https://\(host)/favicon.ico")
    }
}

/// Pages the reader saved from the in-app browser, shown on the 網頁瀏覽 start page
/// so a site they read from is one tap away.
@MainActor
final class BrowserBookmarkStore: ObservableObject {
    static let shared = BrowserBookmarkStore()

    @Published private(set) var bookmarks: [BrowserBookmark] = []

    private let storageKey = "browserBookmarks.v1"
    private let seededDefaultsKey = "browserBookmarks.seededDefaults.v1"
    private let defaults = UserDefaults.standard

    init() {
        load()
        seedDefaultsIfNeeded()
    }

    func isBookmarked(_ url: String) -> Bool {
        let key = Self.normalized(url)
        return bookmarks.contains { Self.normalized($0.url) == key }
    }

    /// Adds `url`, or removes it when it is already bookmarked.
    func toggle(title: String, url: String) {
        let key = Self.normalized(url)
        guard !key.isEmpty else { return }
        if let index = bookmarks.firstIndex(where: { Self.normalized($0.url) == key }) {
            bookmarks.remove(at: index)
        } else {
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            bookmarks.insert(
                BrowserBookmark(
                    title: cleanTitle.isEmpty ? (URL(string: url)?.host ?? url) : cleanTitle,
                    url: url,
                    createdAt: Date()
                ),
                at: 0
            )
        }
        save()
    }

    func remove(_ bookmark: BrowserBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }

    /// `List`'s `onMove` contract: `destination` is an offset in the list before the move.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { bookmarks[$0] }
        var remaining = bookmarks.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        bookmarks = remaining
        save()
    }

    /// The links 探索's old start page offered — 番茄登入 and the search engines — become
    /// bookmarks once, so they stay one tap away and go like any other bookmark when the
    /// reader deletes them.
    private func seedDefaultsIfNeeded() {
        guard !defaults.bool(forKey: seededDefaultsKey) else { return }
        defaults.set(true, forKey: seededDefaultsKey)
        let links = [(title: localized("番茄登入"), url: "https://fanqienovel.com/")]
            + SearchEngine.allCases.map { (title: $0.rawValue, url: $0.startURL) }
        for link in links where !isBookmarked(link.url) {
            bookmarks.append(BrowserBookmark(title: link.title, url: link.url, createdAt: Date()))
        }
        save()
    }

    private static func normalized(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            bookmarks = try JSONDecoder().decode([BrowserBookmark].self, from: data)
        } catch {
            AppLogger.cache("⟐ browser bookmarks could not be read", error: error)
        }
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(bookmarks), forKey: storageKey)
        } catch {
            AppLogger.cache("⟐ browser bookmarks could not be saved", error: error)
        }
    }
}
