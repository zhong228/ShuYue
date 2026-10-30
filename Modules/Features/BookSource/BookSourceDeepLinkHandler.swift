import Foundation
import Combine

// MARK: - BookSourceDeepLinkHandler

// State machine driving the system-level source import sheet. The App entry
// point calls `handle(url:)` from `.onOpenURL`; when the URL is a valid
// source-import deep link, the handler flips to `.confirming` and the App
// presents `BookSourceImportConfirmSheet` bound to this handler. The user then
// confirms, the handler downloads and imports — book sources via the same
// `BookSourceStore` path the in-app WebView importer uses, RSS subscriptions
// via `LegadoSourceJSONParser` + `RSSStore` — and reports the result.
//
// Book sources go through `BookSourceImportCoordinator` (parse, review, then
// write the selected rows); RSS subscriptions write directly, mirroring the
// RSS screen's own JSON importer, which has no review list either.
@MainActor
final class BookSourceDeepLinkHandler: ObservableObject {
    enum Phase: Equatable {
        case idle
        case confirming(sourceURL: URL, kind: BookSourceImportDeepLink.ImportKind)
        /// Downloading and parsing. Nothing is written in this phase.
        case importing
        /// The parsed pack is on screen in the confirmation list, awaiting the user's picks.
        /// The plan itself lives on `coordinator`; a phase has to stay `Equatable`.
        case reviewing
        case succeeded(count: Int)
        case failed(message: String)
    }

    @Published private(set) var phase: Phase = .idle

    /// Kind of the import currently (or most recently) driven through the
    /// sheet, so the confirm sheet can label book sources vs RSS subscriptions.
    @Published private(set) var activeKind: BookSourceImportDeepLink.ImportKind = .bookSource

    /// Holds the confirmation list and its import options. A deep link can arrive while
    /// 書源管理 is nowhere on screen, so this route owns its own coordinator rather than
    /// reaching for that screen's.
    let coordinator = BookSourceImportCoordinator()

    /// Entry point from `.onOpenURL`. Non-import URLs are silently dropped.
    /// A new import URL replaces a finished (succeeded/failed) phase, but is
    /// ignored while an import is already in flight so we never cancel a
    /// download the user already confirmed.
    func handle(url: URL) {
        if case .importing = phase { return }
        guard let link = BookSourceImportDeepLink.importLink(from: url) else {
            return
        }
        activeKind = link.kind
        phase = .confirming(sourceURL: link.sourceURL, kind: link.kind)
    }

    /// Called by the confirm sheet's primary button. Downloads the source URL
    /// and imports it through the store matching its declared kind.
    func confirm() {
        guard case .confirming(let sourceURL, let kind) = phase else { return }
        phase = .importing
        Task { await performImport(from: sourceURL, kind: kind) }
    }

    func cancel() {
        switch phase {
        case .confirming:
            phase = .idle
        case .reviewing:
            coordinator.cancel()
            phase = .idle
        default:
            return
        }
    }

    /// Writes the rows ticked in the confirmation list.
    func commitReview() {
        guard case .reviewing = phase else { return }
        do {
            phase = .succeeded(count: try coordinator.confirmImport())
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    /// Dismiss the result state and close the sheet.
    func finish() {
        phase = .idle
    }

    private func performImport(
        from sourceURL: URL,
        kind: BookSourceImportDeepLink.ImportKind
    ) async {
        do {
            let (data, _) = try await MediaSession.shared.data(from: sourceURL)
            guard !data.isEmpty else {
                phase = .failed(message: localized("無法讀取書源資料"))
                return
            }
            switch kind {
            case .rssSource:
                importRSS(data: data)
            case .bookSource:
                presentBookSourceReview(data: data, sourceURL: sourceURL)
            case .auto:
                // The link did not declare a type: RSS JSON first (Legado book
                // sources carry `bookSourceName`/`bookSourceUrl`, so the RSS
                // parser yields nothing for them), book sources otherwise.
                let rssSources = (try? LegadoSourceJSONParser.parse(data: data)) ?? []
                if rssSources.isEmpty {
                    presentBookSourceReview(data: data, sourceURL: sourceURL)
                } else {
                    activeKind = .rssSource
                    commitRSS(rssSources)
                }
            }
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    /// Parses and writes RSS subscriptions, mirroring the RSS screen's JSON
    /// importer (direct write, no review list).
    private func importRSS(data: Data) {
        do {
            let sources = try LegadoSourceJSONParser.parse(data: data)
            guard !sources.isEmpty else {
                phase = .failed(message: localized("連結中沒有可匯入的訂閱源"))
                return
            }
            commitRSS(sources)
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    private func commitRSS(_ sources: [RSSSource]) {
        let added = RSSStore.shared.addSourcesReturningAdded(sources)
        phase = .succeeded(count: added.count)
    }

    /// Parses book sources only and shows the confirmation list. Parse-only:
    /// the user picks what to keep, so a link can no longer overwrite sources
    /// without showing what it contains.
    private func presentBookSourceReview(data: Data, sourceURL: URL) {
        let ext = sourceURL.pathExtension.isEmpty ? "json" : sourceURL.pathExtension
        do {
            let sources = try BookSourceStore.shared.parseForImport(data: data, fileExtension: ext)
            coordinator.present(sources: sources)
            phase = .reviewing
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }
}
