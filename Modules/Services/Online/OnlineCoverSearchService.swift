import Foundation

/// 封面搜索 — covers looked up on the open web rather than in the user's sources.
///
/// This is Legado's 封面規則 (`BookCover.searchCover`) without the rule plumbing:
/// its shipped default rule queries 推書君 and 一片書喽 from JavaScript, matches
/// the result's title and author against the book, and returns the artwork. The
/// same two endpoints are queried here directly, because the rule's JS needs a
/// `data:` search URL and a `com.jayway.jsonpath` binding that our engine has no
/// other use for. There is no rule editor yet — if these endpoints ever move,
/// this is the single place that changes.
///
/// Legado stops at the first match; this keeps every distinct cover so the user
/// picks from a grid instead of accepting whatever answered first.
enum OnlineCoverSearchService {

    struct Result: Equatable {
        let coverUrl: String
        /// The site the cover came from, shown under the thumbnail.
        let providerName: String
    }

    private enum Provider {
        case tuishujun
        case ypshuo

        var displayName: String {
            switch self {
            case .tuishujun: return localized("推書君")
            case .ypshuo: return localized("一片書喽")
            }
        }

        func requestURL(query: String) -> URL? {
            var components: URLComponents?
            switch self {
            case .tuishujun:
                components = URLComponents(string: "https://pre-api.tuishujun.com/api/searchBook")
                components?.queryItems = [
                    URLQueryItem(name: "search_value", value: query),
                    URLQueryItem(name: "page", value: "1"),
                    URLQueryItem(name: "pageSize", value: "20"),
                ]
            case .ypshuo:
                components = URLComponents(string: "https://m.ypshuo.com/api/novel/search")
                components?.queryItems = [
                    URLQueryItem(name: "keyword", value: query),
                    URLQueryItem(name: "searchType", value: "1"),
                    URLQueryItem(name: "page", value: "1"),
                ]
            }
            return components?.url
        }

        /// Field names differ per provider; the matching rule does not.
        var fields: (title: String, author: String, cover: String) {
            switch self {
            case .tuishujun: return ("title", "author_nickname", "cover")
            case .ypshuo: return ("novel_name", "author_name", "novel_img")
            }
        }
    }

    /// Covers for `name`/`author`, deduped by URL, in provider order.
    ///
    /// Providers are independent: one being down or slow must not cost the other,
    /// so failures are logged per provider and the rest of the results stand.
    static func searchCovers(name: String, author: String) async -> [Result] {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var results: [Result] = []
        var seen = Set<String>()

        await withTaskGroup(of: [Result].self) { group in
            for provider in [Provider.tuishujun, Provider.ypshuo] {
                group.addTask { await search(provider: provider, name: query, author: author) }
            }
            for await providerResults in group {
                for result in providerResults where seen.insert(result.coverUrl).inserted {
                    results.append(result)
                }
            }
        }
        return results
    }

    private static func search(provider: Provider, name: String, author: String) async -> [Result] {
        guard let url = provider.requestURL(query: name) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(BookCoverLoader.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await MediaSession.dataWithRetry(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                AppLogger.network(
                    "[CoverSearch] \(provider.displayName) HTTP \(http.statusCode)"
                )
                return []
            }
            return parse(data: data, provider: provider, name: name, author: author)
        } catch {
            AppLogger.network(
                "[CoverSearch] \(provider.displayName) request failed", error: error
            )
            return []
        }
    }

    /// Both providers answer `{ data: { data: [ … ] } }`; only the item keys differ.
    private static func parse(
        data: Data,
        provider: Provider,
        name: String,
        author: String
    ) -> [Result] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let items = payload["data"] as? [[String: Any]] else {
            AppLogger.parse("[CoverSearch] \(provider.displayName) returned an unexpected shape")
            return []
        }
        let fields = provider.fields
        return items.compactMap { item in
            guard let rawCover = item[fields.cover] as? String else { return nil }
            let cover = normalizedCoverURL(rawCover)
            guard !cover.isEmpty else { return nil }
            let itemTitle = item[fields.title] as? String ?? ""
            let itemAuthor = item[fields.author] as? String ?? ""
            guard matches(name: name, author: author, itemTitle: itemTitle, itemAuthor: itemAuthor)
            else { return nil }
            return Result(coverUrl: cover, providerName: provider.displayName)
        }
    }

    /// Matches a search result's title/author against the local book.
    ///
    /// Titles match either direction: providers pad titles with volume tags
    /// (推書君 returns 「三体（全集）」 for 「三体」), so a strict one-way `contains`
    /// dropped real hits. Authors contain one another (either direction, because
    /// sources write 「作者：X」, 「X 著」 and bare 「X」 interchangeably). An unknown
    /// local author matches on title alone rather than dropping every candidate —
    /// an imported TXT usually has no author at all.
    private static func matches(
        name: String,
        author: String,
        itemTitle: String,
        itemAuthor: String
    ) -> Bool {
        let localTitle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteTitle = itemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localTitle.isEmpty, titlesMatch(local: localTitle, remote: remoteTitle)
        else { return false }

        let localAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteAuthor = itemAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isUnknownAuthor(localAuthor), !remoteAuthor.isEmpty else { return true }
        return localAuthor.contains(remoteAuthor) || remoteAuthor.contains(localAuthor)
    }

    /// Local imports hard-code Chinese placeholders for a missing author
    /// (BookStore's 未知作者/未知), which is not the `localized("未知作者")` value the
    /// old comparison used — that key reads "Unknown" in English and missed them.
    private static func isUnknownAuthor(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let placeholders: Set<String> = [
            "未知作者", "未知", "佚名", "Unknown", "Unknown Author",
            "著者不明", "작자 미상", "作者不詳",
        ]
        return placeholders.contains(trimmed)
    }

    /// Two book names agree when either contains the other, or when their
    /// trailing parenthetical tags (（全集） / (完結) …) are stripped they still do.
    private static func titlesMatch(local: String, remote: String) -> Bool {
        if local == remote || local.contains(remote) || remote.contains(local) { return true }
        let a = withoutTrailingParenthetical(local)
        let b = withoutTrailingParenthetical(remote)
        return !a.isEmpty && !b.isEmpty && (a.contains(b) || b.contains(a))
    }

    private static func withoutTrailingParenthetical(_ value: String) -> String {
        var result = value
        var changed = true
        while changed {
            changed = false
            // Full-width （…） first, then half-width (…): 「三体（全集）」 → 「三体」.
            for pattern in [#"（[^（）]*）$"#, #"\([^()]*\)$"#] {
                if let range = result.range(of: pattern, options: .regularExpression) {
                    let trimmed = result[..<range.lowerBound]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        result = trimmed
                        changed = true
                        break
                    }
                }
            }
        }
        return result
    }

    /// ypshuo answers scheme-relative URLs (`//bookcover.yuewen.com/...`); for
    /// those, `URL(string:)` alone yields a relative URL and the download fails.
    private static func normalizedCoverURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") { return "https:" + trimmed }
        return trimmed
    }
}
