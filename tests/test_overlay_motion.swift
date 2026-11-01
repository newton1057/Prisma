import Foundation
import CoreGraphics

/// Checks that the orb's light changes shape continuously: the pose weights
/// never jump (even when a transition is interrupted) and the beam outline
/// moves smoothly while it bends between the voice horizon, the thinking
/// ring and the waiting fold.
@main
struct TestOverlayMotion {
    static let size = CGSize(width: 198, height: 198)

    static func main() {
        testPoseTimeline()
        testActivityScale()
        testHaloThemes()
        testGeometryIsContinuous()
        testLoopIsSeamless()
        testVoiceHorizonStaysCentred()
        testRowSlide()
        print("Overlay motion continuity passed")
    }

    static func testHaloThemes() {
        precondition(HaloTheme.allCases.count == 10, "expected 10 halo themes, got \(HaloTheme.allCases.count)")
        for theme in HaloTheme.allCases {
            let stops = theme.palette.ringStops
            precondition(stops.count == 7 && stops.first == stops.last, "\(theme): ring palette must close seamlessly")
            var f = frame(voice: 0.5, thinking: 0.3, idle: 0.2)
            f.theme = theme
            let beam = PrismaBeam(frame: f, energy: 0.4, size: size)
            precondition(beam.bloomBands.count == 2 && beam.spectralBands.count == 4, "\(theme): invalid band count")
        }
    }

    /// Waiting orbs shrink to `inactiveScale`, expand smoothly to `activeScale`
    /// when hovered, thinking or speaking, and shrink back once idle again.
    static func testActivityScale() {
        var now = 4_000.0
        let model = OverlayModel()
        model.clock = { now }
        model.hasIdleState = true
        precondition(!model.isActive, "waiting session orb should be inactive")
        precondition(abs(model.frame(at: now).scale - OverlayModel.inactiveScale) < 1e-9,
                     "hidden waiting orb should snap to inactive scale")
        precondition(abs(model.frame(at: now).opacity - OverlayModel.inactiveOpacity) < 1e-9,
                     "hidden waiting orb should snap to inactive opacity")

        model.visible = true
        var activeEvents = 0
        model.onActiveChange = { activeEvents += 1 }

        let dt = 1.0 / 240
        var scales: [Double] = []
        var opacities: [Double] = []
        for i in 0..<720 {
            now = 4_000 + Double(i) * dt
            if i == 24 { model.isHovered = true }       // hover expands
            if i == 120 { model.isHovered = false }     // leave starts shrinking
            if i == 180 { model.isThinking = true }     // interrupted mid-shrink by thinking
            if i == 340 { model.isSpeaking = true; model.isThinking = false } // stays active into speech
            if i == 480 { model.isSpeaking = false }    // returns to waiting
            let f = model.frame(at: now)
            scales.append(f.scale)
            opacities.append(f.opacity)
        }
        for i in 1..<scales.count {
            let s = scales[i]
            precondition(s >= OverlayModel.inactiveScale - 1e-9 && s <= OverlayModel.activeScale + 1e-9,
                         "scale \(s) left bounds")
            let step = abs(s - scales[i - 1])
            precondition(step < 0.004, "scale jumped \(step) in one frame")
            let o = opacities[i]
            precondition(o >= OverlayModel.inactiveOpacity - 1e-9 && o <= OverlayModel.activeOpacity + 1e-9,
                         "opacity \(o) left bounds")
        }
        precondition(abs(scales[339] - OverlayModel.activeScale) < 1e-4, "thinking orb should reach active scale")
        precondition(abs(opacities[339] - OverlayModel.activeOpacity) < 1e-4, "thinking orb should reach active opacity")
        precondition(abs(scales[400] - OverlayModel.activeScale) < 1e-9, "thinking->speaking should stay at active scale")
        precondition(abs(scales.last! - OverlayModel.inactiveScale) < 1e-4, "idle orb should settle back to inactive scale")
        precondition(abs(opacities.last! - OverlayModel.inactiveOpacity) < 1e-4, "idle orb should settle back to inactive opacity")
        precondition(activeEvents == 4, "expected 4 active state changes, got \(activeEvents)")
    }

    /// Orbs making room in the row slide smoothly, keep their momentum when
    /// redirected and land exactly on their place.
    static func testRowSlide() {
        var now = 3_000.0
        let model = OverlayModel()
        model.clock = { now }
        let start = SIMD2<Double>(-1_100, 664)
        let first = SIMD2<Double>(-1_177, 664)
        let second = SIMD2<Double>(-1_023, 664)

        model.glide(from: start, to: first, delay: 0.18, duration: 0.7)
        let dt = 1.0 / 240
        var positions: [SIMD2<Double>] = []
        for i in 0..<480 {
            now = 3_000 + Double(i) * dt
            if i == 96 { model.glide(from: start, to: second, delay: 0, duration: 0.7) } // redirected mid-slide
            if now < 3_000.18 {
                let waiting = model.glidePosition(at: now) - start
                precondition(abs(waiting.x) < 1e-6 && abs(waiting.y) < 1e-6, "orb should wait before sliding")
            }
            positions.append(model.glidePosition(at: now))
        }
        for i in 1..<positions.count {
            let step = abs(positions[i].x - positions[i - 1].x)
            precondition(step < 2.5, "orb jumped \(step) pt in one frame")
            if i + 1 < positions.count {
                let bend = abs(positions[i + 1].x - 2 * positions[i].x + positions[i - 1].x)
                precondition(bend < 0.05, "slide changed speed abruptly (\(bend)) at frame \(i)")
            }
        }
        precondition(positions.last! == second, "orb should land exactly on its place")
        precondition(!model.isGliding(at: now), "slide should be over")
    }

    static func testPoseTimeline() {
        let now = 1_000.0
        let model = OverlayModel()
        model.clock = { now }

        // A hidden orb takes its shape at once instead of animating into it.
        model.hasIdleState = true
        let first = model.frame(at: now)
        precondition(first.idle == 1 && first.voice == 0, "hidden orb should start waiting")
        model.isThinking = true
        let thinking = model.frame(at: now)
        precondition(thinking.thinking == 1, "hidden orb should take the thinking shape at once")

        let story: [(Double, Int)] = [
            (0.5, 0), (0.9, 1), (1.4, 2), (1.7, 0), (4.0, 1), (6.0, 2),
        ]
        let last = simulate(story, duration: 8)
        precondition(last.z > 0.999, "orb should settle back to waiting")

        // Rapid, random interruptions must keep the light valid and smooth.
        var seed: UInt64 = 0x5EED
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        for _ in 0..<200 {
            var events: [(Double, Int)] = []
            var at = 0.05 + 0.5 * random()
            while at < 5 {
                events.append((at, Int(random() * 4)))
                at += 0.05 + 0.85 * random()
            }
            _ = simulate(events, duration: 6)
        }
    }

    /// Runs a sequence of state changes at 240 Hz and checks the pose stays
    /// valid, never jumps, and only changes speed when a new state arrives.
    @discardableResult
    static func simulate(_ events: [(Double, Int)], duration: Double) -> SIMD3<Double> {
        var now = 2_000.0
        let model = OverlayModel()
        model.clock = { now }
        model.hasIdleState = true
        model.visible = true

        let dt = 1.0 / 240
        var next = 0
        var poses: [SIMD3<Double>] = []
        var eventFrames = Set<Int>()
        var frameIndex = 0
        while Double(frameIndex) * dt < duration {
            frameIndex += 1
            let t = Double(frameIndex) * dt
            now = 2_000 + t
            while next < events.count, events[next].0 <= t {
                switch events[next].1 {
                case 0: model.isThinking = true
                case 1: model.isThinking = false; model.isSpeaking = true
                case 2: model.isSpeaking = false
                default: model.isThinking = false
                }
                eventFrames.insert(poses.count)
                next += 1
            }
            let f = model.frame(at: now)
            let sum = f.voice + f.thinking + f.idle
            precondition(abs(sum - 1) < 1e-9, "pose weights must add up to one, got \(sum)")
            precondition(min(f.voice, f.thinking, f.idle) >= 0, "pose weights must stay positive")
            precondition(max(f.voice, f.thinking, f.idle) <= 1, "pose weights must stay below one")
            poses.append(SIMD3(f.voice, f.thinking, f.idle))
        }

        func largest(_ v: SIMD3<Double>) -> Double { max(abs(v.x), abs(v.y), abs(v.z)) }
        for i in 1..<poses.count {
            let step: SIMD3<Double> = poses[i] - poses[i - 1]
            // A one-second quintic moves at most 1.875 per second (0.0078 per step).
            precondition(largest(step) < 0.015, "pose jumped by \(largest(step)) in one frame")
            guard i + 1 < poses.count else { continue }
            if eventFrames.contains(i) || eventFrames.contains(i + 1) || eventFrames.contains(i - 1) { continue }
            let nextStep: SIMD3<Double> = poses[i + 1] - poses[i]
            // Between events the second difference stays near 1e-4; a sudden
            // change of speed would show up as several thousandths.
            precondition(largest(nextStep - step) < 0.0004,
                         "pose speed changed abruptly (\(largest(nextStep - step))) at \(Double(i) * dt)s")
        }
        return poses.last!
    }

    static func frame(voice: Double, thinking: Double, idle: Double, time: Double = 500) -> OrbFrame {
        OrbFrame(time: time, voice: voice, thinking: thinking, idle: idle, speaking: 0, audio: 0,
                 spin: 0.3, sweep: 1.2, idlePhase: 2.37)
    }

    static func outlines(_ f: OrbFrame) -> [PrismaBeam.Outline] {
        let beam = PrismaBeam(frame: f, energy: OrbEnergy.value(for: f), size: size)
        return (beam.bloomBands + beam.spectralBands + [beam.coreBand]).map { beam.outline($0) }
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }

    static func testGeometryIsContinuous() {
        let paths: [(String, (Double) -> OrbFrame)] = [
            ("waiting to thinking", { s in frame(voice: 0, thinking: s, idle: 1 - s) }),
            ("thinking to voice", { s in frame(voice: s, thinking: 1 - s, idle: 0) }),
            ("voice to waiting", { s in frame(voice: 1 - s, thinking: 0, idle: s) }),
        ]
        let steps = 2_000
        for (name, pose) in paths {
            var previous = outlines(pose(0))
            var largest = 0.0
            for i in 1...steps {
                let current = outlines(pose(Double(i) / Double(steps)))
                for (a, b) in zip(previous, current) {
                    for (p, q) in zip(a.outer + a.inner, b.outer + b.inner) {
                        precondition(p.x.isFinite && p.y.isFinite, "\(name): invalid point")
                        largest = max(largest, distance(p, q))
                    }
                }
                previous = current
            }
            // Over 2000 steps a point travelling ~250 pt moves ~0.13 pt per step;
            // a cut or a flipped segment would jump many points at once.
            precondition(largest < 0.6, "\(name): outline jumped \(largest) pt in one step")
        }

        // Light keeps flowing smoothly over time in every pose.
        for pose in [frame(voice: 1, thinking: 0, idle: 0), frame(voice: 0, thinking: 1, idle: 0),
                     frame(voice: 0, thinking: 0, idle: 1), frame(voice: 0.4, thinking: 0.3, idle: 0.3)] {
            var next = pose
            next.time += 1.0 / 60
            next.sweep += 1.4 / 60
            next.spin += 0.1 / 60
            for (x, y) in zip(outlines(pose), outlines(next)) {
                for (p, q) in zip(x.outer, y.outer) {
                    precondition(distance(p, q) < 2.5, "light moved \(distance(p, q)) pt in one frame")
                }
            }
        }
    }

    static func testLoopIsSeamless() {
        for pose in [frame(voice: 0, thinking: 1, idle: 0), frame(voice: 0, thinking: 0, idle: 1)] {
            for shape in outlines(pose) {
                let outerGap = distance(shape.outer.first!, shape.outer.last!)
                let innerGap = distance(shape.inner.first!, shape.inner.last!)
                precondition(outerGap < 0.01 && innerGap < 0.01, "closed loop has a seam")
            }
        }
    }

    static func testVoiceHorizonStaysCentred() {
        let core = outlines(frame(voice: 1, thinking: 0, idle: 0)).last!
        let middle = core.spine[core.spine.count / 2]
        precondition(abs(middle.x - 99) < 0.01, "voice horizon is not centred horizontally")
        precondition(abs(middle.y - 99) < 2.5, "brightest point of the voice horizon left the centre")
    }
}
