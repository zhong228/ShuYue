import Testing
import QuartzCore
@testable import yuedu_app

@Suite("ReaderTurnBurstPacer")
struct ReaderTurnBurstPacerTests {

    @Test("taps with a pause between them all play at 1×")
    func loneTapsPlayAtNormalSpeed() {
        var pacer = ReaderTurnBurstPacer()
        #expect(pacer.registerTap(at: 10) == 1)
        #expect(pacer.registerTap(at: 11) == 1)
        #expect(pacer.registerTap(at: 11 + ReaderTurnBurstPacer.pauseDuration) == 1)
    }

    @Test("a burst winds up over several turns instead of jumping to full speed")
    func burstRampsUp() {
        var pacer = ReaderTurnBurstPacer()
        let gap = 0.1
        // What this rhythm asks for; before the ramp, the second tap got all of it.
        let rhythm = Float(ReaderTurnBurstPacer.naturalTurnDuration / gap)
        var previous = pacer.registerTap(at: 0)
        var speeds: [Float] = []
        for tap in 1...6 {
            let speed = pacer.registerTap(at: Double(tap) * gap)
            #expect(speed > previous)
            #expect(speed < rhythm)
            speeds.append(speed)
            previous = speed
        }
        // The first step is a partial one, and no step is bigger than it.
        #expect(abs(speeds[0] - (1 + (rhythm - 1) * ReaderTurnBurstPacer.rampFraction)) < 0.0001)
        let steps = zip(speeds, speeds.dropFirst()).map { $1 - $0 }
        #expect(steps.allSatisfy { $0 < speeds[0] - 1 })
        // And it does get there.
        #expect(rhythm - speeds[5] < 0.05)
    }

    @Test("speed never passes the maximum, however fast the taps")
    func speedIsCapped() {
        var pacer = ReaderTurnBurstPacer()
        for tap in 0..<40 {
            let speed = pacer.registerTap(at: Double(tap) * 0.01)
            #expect(speed <= ReaderTurnBurstPacer.maximumSpeed)
        }
        #expect(ReaderTurnBurstPacer.maximumSpeed - pacer.speed < 0.01)
        // Two commands in the same instant count as the fastest rhythm, not a crash.
        #expect(pacer.registerTap(at: 0.39) <= ReaderTurnBurstPacer.maximumSpeed)
    }

    @Test("tapping a little slower eases the speed down rather than dropping to 1×")
    func slowingDownEasesOff() {
        var pacer = ReaderTurnBurstPacer()
        var now = 0.0
        for _ in 0..<10 {
            pacer.registerTap(at: now)
            now += 0.1
        }
        let fast = pacer.speed
        let eased = pacer.registerTap(at: now + 0.2)
        #expect(eased < fast)
        #expect(eased > 1)
    }

    @Test("a pause ends the burst")
    func pauseResets() {
        var pacer = ReaderTurnBurstPacer()
        for tap in 0..<10 { pacer.registerTap(at: Double(tap) * 0.1) }
        #expect(pacer.speed > 2)
        #expect(pacer.registerTap(at: 0.9 + ReaderTurnBurstPacer.pauseDuration) == 1)
    }

    @Test("changing a layer's speed mid-animation keeps its clock where it was")
    func layerClockStaysContinuous() {
        let layer = CALayer()
        let now = CACurrentMediaTime()
        let before = layer.convertTime(now, from: nil)

        ReaderTurnLayerClock.setSpeed(2.5, on: layer, at: now)
        #expect(abs(layer.convertTime(now, from: nil) - before) < 0.0001)
        // From here on it runs 2.5× as fast.
        #expect(abs(layer.convertTime(now + 0.1, from: nil) - (before + 0.25)) < 0.0001)

        // A second change, later, is just as seamless.
        let later = now + 0.1
        let atLater = layer.convertTime(later, from: nil)
        ReaderTurnLayerClock.setSpeed(3, on: layer, at: later)
        #expect(abs(layer.convertTime(later, from: nil) - atLater) < 0.0001)
        #expect(abs(layer.convertTime(later + 0.1, from: nil) - (atLater + 0.3)) < 0.0001)

        ReaderTurnLayerClock.reset(layer)
        #expect(layer.speed == 1)
        #expect(abs(layer.convertTime(now, from: nil) - now) < 0.0001)
    }
}
