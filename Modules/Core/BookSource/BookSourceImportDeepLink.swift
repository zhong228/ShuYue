import Foundation

// MARK: - BookSourceImportDeepLink

// Pure parser for source-import deep links. Shared by the in-app WebView
// interceptor (`JsBridgeBrowserView`) and the system-level URL handler wired in
// `yuedu_appApp.onOpenURL`, so there is exactly one implementation path for
// importing sources from a deep link.
//
// Supported shapes (the `src` / `url` query item holds the real source URL):
//   yuedu://booksource/importOnline?src=URL   – legacy self-hosted shape (book sources)
//   yuedu://import/{auto,bookSource,…}?src=URL – Legado-style shape on the
//                                                `yuedu` scheme (the form most
//                                                shared update pages emit today)
//   legado://import/{auto,bookSource,rssSource,…}?src=URL – Legado's own scheme
//
// The first path segment under `import` selects the payload kind, matching
// Legado's routing: `bookSource`/`bookSourceUrl` import book sources,
// `rssSource`/`rssSources` import RSS subscriptions (yckceo and friends emit
// `legado://import/rssSource?src=…` for their 一键导入 buttons), and anything
// else (notably `auto`) sniffs the downloaded payload.
enum BookSourceImportDeepLink {
    enum ImportKind: Equatable {
        case bookSource
        case rssSource
        /// The link does not state a payload type (e.g. `import/auto`); the
        /// downloaded data decides — RSS JSON first, book sources otherwise.
        case auto
    }

    struct ImportLink: Equatable {
        let sourceURL: URL
        let kind: ImportKind
    }

    /// Parses a deep link into the source payload URL plus its declared kind,
    /// or `nil` when `url` is not one of the supported import shapes.
    static func importLink(from url: URL) -> ImportLink? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        let host = url.host?.lowercased()
        let path = url.path.lowercased()

        // Legacy self-hosted deep link: yuedu://booksource/importOnline?src=URL
        let isLegacyYuedu = scheme == "yuedu"
            && host == "booksource"
            && path == "/importonline"
        // Legado-style deep link (either scheme): …://import/{…}?src=URL.
        let isLegadoStyleImport =
            (scheme == "yuedu" || scheme == "legado") && host == "import"

        guard isLegacyYuedu || isLegadoStyleImport else { return nil }

        let kind: ImportKind
        if isLegacyYuedu {
            kind = .bookSource
        } else {
            // First path segment under `import` routes the payload kind.
            let route = path.split(separator: "/").first.map(String.init) ?? ""
            switch route {
            case "rsssource", "rsssources", "rss":
                kind = .rssSource
            case "booksource", "booksourceurl", "booksources":
                kind = .bookSource
            default:
                kind = .auto
            }
        }

        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let sourceString = components.queryItems?.first(where: {
                let name = $0.name.lowercased()
                return name == "src" || name == "url"
            })?.value,
            !sourceString.isEmpty,
            let sourceURL = URL(string: sourceString)
        else { return nil }
        return ImportLink(sourceURL: sourceURL, kind: kind)
    }
}
