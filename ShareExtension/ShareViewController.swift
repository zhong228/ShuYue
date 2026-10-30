import UIKit
import UniformTypeIdentifiers

/// Accepts three kinds of share payloads:
///   1. Remote links (browser → share sheet) — queued as URLs.
///   2. Book-source JSON files (Files app / WeChat / QQ / browser downloads → share
///      sheet) — staged as generic files; the main app's classifier routes them to
///      the book-source review list.
///   3. Local book files (TXT / EPUB / PDF / audio / manga / any readable document →
///      share sheet) — staged as generic files; the main app's classifier routes
///      them to the local-book import pipeline.
/// A Share extension cannot launch its containing app through a supported API, so all
/// payloads are stashed in the app group and merged on the next app launch.
final class ShareViewController: UIViewController {
    /// Must match `SharedImportQueueDrainer.appGroupID` in the main app.
    private static let appGroupID = "group.com.zhong228.shuyue"
    /// Must match `SharedImportQueueDrainer.payloadQueueKey`.
    private static let payloadQueueKey = "shared_import_items_queue"
    /// Must match `SharedImportQueueDrainer.payloadDirectoryName`.
    private static let payloadDirectoryName = "shared_import_payloads"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            finish(success: false, message: localized("无法读取分享内容"))
            return
        }
        let isFileURL = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        if !isFileURL, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            // A bare URL (http/https), not a file-backed URL, is a link to queue.
            loadRemoteLink(provider)
        } else {
            // Everything else is treated as a generic file payload: bookmark-source
            // JSON and local books (TXT/EPUB/PDF/…) alike. The main app classifies
            // the content and picks the right pipeline, so the share extension
            // never needs to guess whether a .json is a source or a book.
            loadSharedFile(provider)
        }
    }

    // MARK: - Remote link payload

    private func loadRemoteLink(_ provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.finish(success: false, message: error.localizedDescription)
                    return
                }
                guard let url = item as? URL else {
                    self.finish(success: false, message: localized("无法读取分享连结"))
                    return
                }
                // Some third-party apps share local files via public.url with a
                // file:// scheme instead of public.file-url. Treat them as file
                // payloads so the importer classifies them correctly.
                if url.isFileURL {
                    do {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        guard !data.isEmpty else {
                            self.finish(success: false, message: localized("分享档案为空"))
                            return
                        }
                        let name = provider.suggestedName ?? url.lastPathComponent
                        try self.enqueueFile(data: data, suggestedName: name, typeIdentifier: UTType.data.identifier)
                    } catch {
                        self.finish(success: false, message: error.localizedDescription)
                    }
                    return
                }
                guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                    self.finish(success: false, message: localized("无法读取分享连结"))
                    return
                }
                self.enqueueLink(url)
            }
        }
    }

    private func enqueueLink(_ url: URL) {
        do {
            guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
                finish(success: false, message: localized("无法储存分享连结"))
                return
            }
            let encoded = try JSONEncoder().encode(LinkPayload(remoteURLString: url.absoluteString))
            append(encoded, toKey: Self.payloadQueueKey, in: defaults)
            finish(success: true, message: localized("连结已储存，下次开启书悦时汇入。"))
        } catch {
            finish(success: false, message: error.localizedDescription)
        }
    }

    // MARK: - Generic file payload (books, book sources, RSS, rules, themes)

    /// Picks the most specific registered type the provider offers that we can read:
    /// JSON first, then plain text/content/data fallbacks — third-party apps often
    /// register a dynamic `dyn.*` UTI that still conforms to `public.data`.
    private static func readableType(from provider: NSItemProvider) -> String? {
        let preferences = [
            UTType.json.identifier,
            UTType.plainText.identifier,
            UTType.text.identifier,
            UTType.content.identifier,
            UTType.data.identifier
        ]
        return preferences.first { provider.hasItemConformingToTypeIdentifier($0) }
            ?? provider.registeredTypeIdentifiers.first
    }

    private func loadSharedFile(_ provider: NSItemProvider) {
        guard let typeIdentifier = Self.readableType(from: provider) else {
            finish(success: false, message: localized("无法读取分享内容"))
            return
        }
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.finish(success: false, message: error.localizedDescription)
                    return
                }
                do {
                    try self.stageAndEnqueue(item: item, provider: provider, typeIdentifier: typeIdentifier)
                } catch {
                    self.finish(success: false, message: error.localizedDescription)
                }
            }
        }
    }

    private func stageAndEnqueue(item: NSSecureCoding?, provider: NSItemProvider, typeIdentifier: String) throws {
        let data: Data
        let suggestedName: String?
        switch item {
        case let url as URL:
            suggestedName = provider.suggestedName ?? url.lastPathComponent
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            data = try Data(contentsOf: url)
        case let dataValue as Data:
            suggestedName = provider.suggestedName
            data = dataValue
        case let dataValue as NSData:
            suggestedName = provider.suggestedName
            data = dataValue as Data
        case let stringValue as String:
            suggestedName = provider.suggestedName
            data = Data(stringValue.utf8)
        case let stringValue as NSString:
            suggestedName = provider.suggestedName
            data = Data((stringValue as String).utf8)
        default:
            throw ShareEnqueueError.unreadableItem
        }
        guard !data.isEmpty else {
            throw ShareEnqueueError.emptyFile
        }
        try enqueueFile(data: data, suggestedName: suggestedName, typeIdentifier: typeIdentifier)
    }

    /// Stages the file inside the App Group and queues a `.file` payload.
    /// The main app's `SharedImportQueueDrainer` classifies the content on drain.
    private func enqueueFile(data: Data, suggestedName: String?, typeIdentifier: String) throws {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            throw ShareEnqueueError.missingAppGroup
        }
        let payloadDirectory = container
            .appendingPathComponent(Self.payloadDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: payloadDirectory, withIntermediateDirectories: true)

        // Unique on-disk name so two same-named shares never collide; the original
        // name is preserved as `suggestedFilename` so the shelf title stays intact.
        let baseName = Self.safeFilename(suggestedName: suggestedName, typeIdentifier: typeIdentifier)
        let storedName = "\(UUID().uuidString)-\(baseName)"
        let target = payloadDirectory.appendingPathComponent(storedName)
        try data.write(to: target, options: .atomic)

        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            try? FileManager.default.removeItem(at: target)
            throw ShareEnqueueError.missingAppGroup
        }
        let payload = FilePayload(
            relativePath: storedName,
            suggestedFilename: baseName,
            typeIdentifier: typeIdentifier
        )
        let encoded = try JSONEncoder().encode(payload)
        append(encoded, toKey: Self.payloadQueueKey, in: defaults)
        finish(success: true, message: localized("档案已储存，下次开启书悦时汇入。"))
    }

    /// Never let a shared name escape the payload directory; fall back to the
    /// preferred extension of the registered type when no name is available.
    private static func safeFilename(suggestedName: String?, typeIdentifier: String) -> String {
        var name = (suggestedName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        if name.isEmpty || name == "." || name == ".." {
            let ext = UTType(typeIdentifier)?.preferredFilenameExtension ?? "dat"
            name = "shared-\(UUID().uuidString.prefix(8)).\(ext)"
        }
        return name
    }

    private func append(_ encoded: Data, toKey key: String, in defaults: UserDefaults) {
        var pending = defaults.array(forKey: key) as? [Data] ?? []
        pending.append(encoded)
        defaults.set(pending, forKey: key)
        defaults.synchronize()
    }

    private func finish(success: Bool, message: String) {
        let alert = UIAlertController(title: localized(success ? "汇入成功" : "汇入失败"),
                                      message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("关闭"), style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        })
        present(alert, animated: true)
    }

    enum ShareEnqueueError: LocalizedError {
        case unreadableItem
        case emptyFile
        case missingAppGroup

        var errorDescription: String? {
            switch self {
            case .unreadableItem: return localized("无法读取分享档案")
            case .emptyFile: return localized("分享档案为空")
            case .missingAppGroup: return localized("无法存取共用的储存空间")
            }
        }
    }
}

/// Matches the main app's generic payload queue (`QueuedPayload.storageKind == "file"`).
private struct FilePayload: Encodable {
    var id = UUID().uuidString
    var storageKind = "file"
    var relativePath: String
    var remoteURLString: String? = nil
    var suggestedFilename: String?
    var typeIdentifier: String?
    var createdAt = Date()
}

/// Matches the main app's generic payload queue (`QueuedPayload.storageKind == "remoteURL"`).
private struct LinkPayload: Encodable {
    var id = UUID().uuidString
    var storageKind = "remoteURL"
    var relativePath: String? = nil
    var remoteURLString: String
    var suggestedFilename: String? = nil
    var typeIdentifier: String? = nil
    var createdAt = Date()
}

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}