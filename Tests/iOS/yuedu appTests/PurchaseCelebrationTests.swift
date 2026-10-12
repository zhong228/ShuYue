import Foundation
import SwiftUI
import Testing
@testable import yuedu_app

@Suite("Purchase celebration")
struct PurchaseCelebrationTests {
    private let canvas = CGSize(width: 390, height: 844)

    private func burst(seed: UInt64 = 42) -> ConfettiBurst {
        ConfettiBurst(count: DSLayout.celebrationConfettiCount, colors: DSColor.celebration.count, seed: seed)
    }

    @Test("a burst is a moment, not a loop: it ends within the longest delay plus fall")
    func burstEnds() {
        let confetti = burst()
        #expect(confetti.pieces.count == DSLayout.celebrationConfettiCount)
        #expect(confetti.duration > 0)
        #expect(confetti.duration <= ConfettiBurst.delayRange.upperBound + ConfettiBurst.fallRange.upperBound)
    }

    /// A hair before a piece's fall ends: `delay + fall - delay` can round past `fall`.
    private func endOfFall(_ piece: ConfettiBurst.Piece) -> TimeInterval {
        piece.delay + piece.fall - 1e-6
    }

    @Test("every piece enters above the top edge and leaves below the bottom one")
    func piecesCrossTheWholeCanvas() throws {
        let confetti = burst()
        for piece in confetti.pieces {
            let first = try #require(confetti.frame(of: piece, at: piece.delay, in: canvas))
            #expect(first.center.y + piece.height / 2 <= 0, "a piece must not pop into view")
            let last = try #require(confetti.frame(of: piece, at: endOfFall(piece), in: canvas))
            #expect(last.center.y - piece.height / 2 >= canvas.height, "a piece must not pop out of view")
        }
    }

    @Test("a piece is drawn only between its start and the end of its fall")
    func piecesAppearOnlyWhileFalling() {
        let confetti = burst()
        for piece in confetti.pieces {
            #expect(confetti.frame(of: piece, at: piece.delay - 0.01, in: canvas) == nil)
            #expect(confetti.frame(of: piece, at: piece.delay + piece.fall + 0.01, in: canvas) == nil)
        }
        let afterward = confetti.pieces.compactMap { confetti.frame(of: $0, at: confetti.duration + 0.01, in: canvas) }
        #expect(afterward.isEmpty, "nothing is left on screen once the burst is over")
    }

    @Test("pieces fade out on the way down instead of vanishing")
    func piecesFadeOut() throws {
        let confetti = burst()
        let piece = try #require(confetti.pieces.first)
        let midway = try #require(confetti.frame(of: piece, at: piece.delay + piece.fall / 2, in: canvas))
        #expect(midway.opacity == 1)
        let end = try #require(confetti.frame(of: piece, at: endOfFall(piece), in: canvas))
        #expect(end.opacity < 0.001)
    }

    @Test("a seed replays the same burst; the page passes a fresh one each time")
    func seedIsReplayable() {
        #expect(burst(seed: 7) == burst(seed: 7))
        #expect(burst(seed: 7) != burst(seed: 8))
    }

    @Test("every piece takes its color from the palette")
    func colorsStayInThePalette() {
        #expect(burst().pieces.allSatisfy { (0..<DSColor.celebration.count).contains($0.color) })
    }

    // MARK: - Timeline

    @Test("the confetti's timeline stops at the end instead of ticking while the page stays open")
    func scheduleIsFinite() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let end = start.addingTimeInterval(2)
        let schedule = FiniteTimelineSchedule(start: start, end: end, interval: 0.5)

        let entries = schedule.entries(from: start, mode: .normal)
        #expect(entries.first == start)
        #expect(entries.last == end)
        #expect(entries.count == 5)
        #expect(zip(entries, entries.dropFirst()).allSatisfy { $0 < $1 })

        #expect(schedule.entries(from: end.addingTimeInterval(1), mode: .normal) == [end])
        #expect(schedule.entries(from: start, mode: .lowFrequency) == [end])
    }
}
