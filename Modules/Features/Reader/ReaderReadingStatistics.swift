import Foundation

/// Session-owned bookkeeping, not a dependency of the whole reader view.
/// Progress and clock observers already refresh the bars that consume it.
@MainActor
final class ReaderReadingStatistics {
    var tracker: ReadingStatsSessionTracker?
}
