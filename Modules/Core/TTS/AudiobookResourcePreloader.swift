import Foundation

/// Resolves the playable links of the chapters on either side of the one that just became
/// ready — legado's `ResourceUrlPreloader` (huajideshutiao/legado,
/// `data/src/commonMain/kotlin/io/legado/app/model/ResourceUrlPreloader.kt`, driven from
/// `AudioPlayManager.preloadNeighbors`). Legado-E and legado-with-MD3 have no look-ahead;
/// their players start resolving the next chapter only when the current one ends.
///
/// The contract carried over from legado:
/// - The window is fixed at ±1, next chapter first: audio links are mostly time-signed, so
///   resolving further ahead only produces links that expire before they are played.
/// - One chapter at a time, never concurrently, so a look-ahead never doubles the load on
///   the source the listener is waiting on.
/// - Every call supersedes the previous round, and the player cancels the round before it
///   resolves a chapter the listener asked for.
/// - A chapter that fails is reported and the round moves on; playback resolves that chapter
///   again when it gets there.
///
/// What a resolved link is for is the caller's business: `AudiobookPlayer` hands the next
/// chapter's to `AVQueuePlayer`, so AVFoundation can preroll it before the current chapter
/// ends.
@MainActor
final class AudiobookResourcePreloader {
    private var task: Task<Void, Never>?
    private var round = 0

    /// The chapters legado resolves around `center`, in its order: the next chapter is the
    /// likelier one to be played.
    nonisolated static func neighborIndices(around center: Int, chapterCount: Int) -> [Int] {
        [center + 1, center - 1].filter { $0 >= 0 && $0 < chapterCount }
    }

    func preload(
        indices: [Int],
        resolve: @escaping @MainActor (Int) async throws -> ChapterAudio,
        onResolved: @escaping @MainActor (Int, ChapterAudio) -> Void,
        onFailure: @escaping @MainActor (Int, Error) -> Void
    ) {
        cancel()
        guard !indices.isEmpty else { return }
        round += 1
        let thisRound = round
        task = Task { @MainActor [weak self] in
            defer { self?.finishRound(thisRound) }
            for index in indices {
                if Task.isCancelled { return }
                do {
                    let audio = try await resolve(index)
                    if Task.isCancelled { return }
                    onResolved(index, audio)
                } catch {
                    // A superseded round ends quietly: switching chapters is not a failure.
                    if Task.isCancelled || error is CancellationError { return }
                    onFailure(index, error)
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func finishRound(_ finished: Int) {
        // Only the latest round may clear the slot: a cancelled round's `defer` runs after
        // its successor has already taken it.
        if finished == round { task = nil }
    }
}
