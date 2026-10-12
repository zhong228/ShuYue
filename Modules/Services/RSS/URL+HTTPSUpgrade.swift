import Foundation

extension URL {
    func upgradedToHTTPS() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              components.scheme == "http" else {
            return self
        }
        components.scheme = "https"
        return components.url ?? self
    }
}

extension String {
    var httpsUpgradedURL: URL? {
        URL(string: self)?.upgradedToHTTPS()
    }

    /// Upgrade only navigational `href` attributes to https. Media `src`
    /// attributes (img/video/audio/source/iframe) are intentionally left on
    /// their original scheme: many RSS sites still serve covers and clips over
    /// plain http, and rewriting `src` to https made those assets fail to load
    /// (ATS allows arbitrary loads in this app, so http media works fine).
    func upgradingHTTPHrefsInHTML() -> String {
        replacingOccurrences(
            of: #"((?:href)\s*=\s*")http://"#,
            with: "$1https://",
            options: .regularExpression
        )
    }
}
