import Foundation

/// Deletes what the retired on-device semantic-search model left behind.
///
/// The optional vector tier was removed on 2026-09-24. A reader who had downloaded its model
/// still has about 258 MB of it in Application Support, plus the download address in
/// defaults; this removes both. It is idempotent: after the first run there is nothing left
/// to find. Delete this file once no install from before that date can still carry the model.
enum AIRetiredEmbeddingCleanup {
    static let directoryName = "AIEmbedding"
    static let sourceURLKey = "yd_ai_embedding_source_url"

    static func run(
        applicationSupport: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        defaults.removeObject(forKey: sourceURLKey)
        guard let applicationSupport else { return }
        let directory = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        do {
            try fileManager.removeItem(at: directory)
            AppLogger.info("Removed the retired AI embedding model")
        } catch {
            AppLogger.error("Could not remove the retired AI embedding model", error: error)
        }
    }
}
