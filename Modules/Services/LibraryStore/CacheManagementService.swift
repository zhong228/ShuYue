import Foundation

enum CacheCategory: String, CaseIterable, Identifiable, Sendable {
    case chapters
    case ttsAudio
    case mangaImages
    case covers
    case diagnostics
    case remoteBooks

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .chapters: return "章节快取"
        case .ttsAudio: return "听书音频快取"
        case .mangaImages: return "漫画图片快取"
        case .covers: return "封面图片快取"
        case .diagnostics: return "诊断纪录"
        case .remoteBooks: return "远端书籍快取"
        }
    }

    var clearTitleKey: String {
        switch self {
        case .chapters: return "清除章节快取"
        case .ttsAudio: return "清除音频快取"
        case .mangaImages: return "清除漫画快取"
        case .covers: return "清除封面快取"
        case .diagnostics: return "清除诊断纪录"
        case .remoteBooks: return "清除远端书籍快取"
        }
    }

    var detailKey: String {
        switch self {
        case .chapters: return "小说正文内容的离线快取"
        case .ttsAudio: return "TTS 合成的音频文件快取"
        case .mangaImages: return "漫画页面图片的离线快取"
        case .covers: return "书籍封面图片的快取"
        case .diagnostics: return "设定 → 诊断与回报 显示的日志与崩溃记录"
        case .remoteBooks: return "线上阅读暂存；清除时保留正在阅读的内容、进度与离线副本"
        }
    }

    var systemImage: String {
        switch self {
        case .chapters: return "doc.text"
        case .ttsAudio: return "waveform"
        case .mangaImages: return "photo.on.rectangle.angled"
        case .covers: return "photo"
        case .diagnostics: return "stethoscope"
        case .remoteBooks: return "books.vertical"
        }
    }
}

struct CacheStorageRoots: Equatable, Sendable {
    var chapters: URL
    var ttsAudio: URL
    var mangaImages: URL
    var covers: URL
    var diagnostics: URL
    var remoteBooks: URL

    init(chapters: URL, ttsAudio: URL, mangaImages: URL, covers: URL, diagnostics: URL, remoteBooks: URL? = nil) {
        self.chapters = chapters
        self.ttsAudio = ttsAudio
        self.mangaImages = mangaImages
        self.covers = covers
        self.diagnostics = diagnostics
        self.remoteBooks = remoteBooks ?? chapters.deletingLastPathComponent().appendingPathComponent("RemoteLibrary", isDirectory: true)
    }

    static var live: CacheStorageRoots {
        CacheStorageRoots(
            chapters: StorageLocations.onlineCache,
            ttsAudio: StorageLocations.ttsAudioCache,
            mangaImages: StorageLocations.mangaCache,
            covers: StorageLocations.covers,
            diagnostics: StorageLocations.diagnostics,
            remoteBooks: StorageLocations.remoteLibraryCache
        )
    }

    subscript(category: CacheCategory) -> URL {
        switch category {
        case .chapters: return chapters
        case .ttsAudio: return ttsAudio
        case .mangaImages: return mangaImages
        case .covers: return covers
        case .diagnostics: return diagnostics
        case .remoteBooks: return remoteBooks
        }
    }
}

struct CacheStorageSnapshot: Equatable, Sendable {
    var chapters: Int64 = 0
    var ttsAudio: Int64 = 0
    var mangaImages: Int64 = 0
    var covers: Int64 = 0
    var diagnostics: Int64 = 0
    var remoteBooks: Int64 = 0

    subscript(category: CacheCategory) -> Int64 {
        switch category {
        case .chapters: return chapters
        case .ttsAudio: return ttsAudio
        case .mangaImages: return mangaImages
        case .covers: return covers
        case .diagnostics: return diagnostics
        case .remoteBooks: return remoteBooks
        }
    }

    var total: Int64 {
        chapters + ttsAudio + mangaImages + covers + diagnostics + remoteBooks
    }
}

enum CacheManagementError: LocalizedError, Equatable {
    case clearFailed(category: CacheCategory, message: String)

    var errorDescription: String? {
        switch self {
        case let .clearFailed(category, message):
            return "Unable to clear \(category.rawValue) cache: \(message)"
        }
    }
}

/// Owns the cache-management use cases exposed by Settings.
///
/// Only app-maintained, re-downloadable artifacts are included here. Imported
/// books, local manga archives, audiobook files, settings, and sync payloads are
/// deliberately outside these roots and are never removed by this service.
final class CacheManagementService: @unchecked Sendable {
    private let fileManager: FileManager
    private let roots: CacheStorageRoots
    /// The live writer behind the diagnostics directory, when there is one. Tests
    /// pass `nil` so clearing stays inside their own fixture instead of reaching
    /// through the singleton to the real device log.
    private let diagnosticLog: DiagnosticLog?
    private let remoteLibraryCache: RemoteLibraryCache
    /// Told when the downloaded-cover directory is emptied, so no screen keeps
    /// drawing a deleted cover and no load already reading one can put it back.
    private let coverPipeline: CoverImagePipeline

    init(
        fileManager: FileManager = .default,
        roots: CacheStorageRoots = .live,
        diagnosticLog: DiagnosticLog? = .shared,
        remoteLibraryCache: RemoteLibraryCache? = nil,
        coverPipeline: CoverImagePipeline = .shared
    ) {
        self.fileManager = fileManager
        self.roots = roots
        self.diagnosticLog = diagnosticLog
        self.coverPipeline = coverPipeline
        self.remoteLibraryCache = remoteLibraryCache
            ?? (roots.remoteBooks == StorageLocations.remoteLibraryCache ? .shared : RemoteLibraryCache(root: roots.remoteBooks))
    }

    func snapshot() -> CacheStorageSnapshot {
        CacheStorageSnapshot(
            chapters: byteCount(in: roots.chapters),
            ttsAudio: byteCount(in: roots.ttsAudio),
            mangaImages: byteCount(in: roots.mangaImages),
            covers: byteCount(in: roots.covers),
            diagnostics: byteCount(in: roots.diagnostics),
            remoteBooks: byteCount(in: roots.remoteBooks)
        )
    }

    func clear(_ category: CacheCategory) throws {
        // The diagnostics directory has a live writer behind it. Deleting the files
        // from under it would race the batched append; `DiagnosticLog.clear()` does
        // the same work on the queue that owns those files.
        if category == .diagnostics, let diagnosticLog {
            diagnosticLog.clear()
            return
        }
        do {
            if category == .remoteBooks {
                try remoteLibraryCache.clearInactive()
                return
            }
            if category == .covers {
                // Also when the delete stops partway: whatever did go must not
                // keep drawing from memory.
                defer { coverPipeline.invalidateDownloadedBookCovers() }
                try clearDirectory(roots[category])
                return
            }
            try clearDirectory(roots[category])
        } catch {
            AppLogger.error(
                "CacheManagementService failed to clear \(category.rawValue)",
                error: error
            )
            throw CacheManagementError.clearFailed(
                category: category,
                message: error.localizedDescription
            )
        }
    }

    func clearAll() throws {
        for category in CacheCategory.allCases {
            try clear(category)
        }
    }

    private func byteCount(in directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey]
                ),
                values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func clearDirectory(_ directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )
        for item in contents {
            try fileManager.removeItem(at: item)
        }
    }
}

// MARK: - Auto Cache Cleanup

/// 自动清理：开启后每次启动检查一次快取总量，达到设定阈值即在后台清除
/// 可重新下載的快取（診斷紀錄除外——排查问题需要它们，且体积很小）。
enum AutoCacheCleanup {
    static let enabledKey = "yd_auto_cache_cleanup_enabled"
    static let thresholdKey = "yd_auto_cache_cleanup_threshold_mb"
    static let thresholdOptions = [200, 500, 1000, 2000]
    static let defaultThresholdMB = 500

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var thresholdMB: Int {
        let stored = UserDefaults.standard.integer(forKey: thresholdKey)
        return thresholdOptions.contains(stored) ? stored : defaultThresholdMB
    }

    /// App 启动时调用一次。任何失败都只记 breadcrumb，绝不影响启动流程。
    static func runIfNeeded(service: CacheManagementService = CacheManagementService()) {
        guard isEnabled else { return }
        let threshold = Int64(thresholdMB) * 1024 * 1024
        Task.detached(priority: .utility) {
            var measurable = service.snapshot()
            measurable.diagnostics = 0
            guard measurable.total >= threshold else { return }
            for category in CacheCategory.allCases where category != .diagnostics {
                try? service.clear(category)
            }
            CrashContext.breadcrumb("auto cache cleanup ran")
        }
    }
}
