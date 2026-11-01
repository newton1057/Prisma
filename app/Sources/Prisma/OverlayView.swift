import SwiftUI
import AppKit

/// Color theme for the orb's halo across waiting, thinking and voice states.
enum HaloTheme: String, CaseIterable, Identifiable {
    case prisma
    case aurora
    case oceano
    case nebula
    case solar
    case amatista
    case esmeralda
    case artico
    case atardecer
    case platino

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prisma: return "Prisma Original (Ámbar y Zafiro)"
        case .aurora: return "Aurora Boreal (Esmeralda y Violeta)"
        case .oceano: return "Océano Abisal (Cian y Cobalto)"
        case .nebula: return "Nebulosa Cósmica (Magenta y Cian)"
        case .solar: return "Fulgor Solar (Oro y Carmesí)"
        case .amatista: return "Amatista Real (Violeta y Rosa)"
        case .esmeralda: return "Bosque Bioluminiscente (Jade y Oro)"
        case .artico: return "Cristal Ártico (Hielo y Plata)"
        case .atardecer: return "Atardecer (Coral e Índigo)"
        case .platino: return "Luz de Luna (Platino y Perla)"
        }
    }

    struct Palette {
        var upperDeep: SIMD3<Double>
        var upperBright: SIMD3<Double>
        var upperMid: SIMD3<Double>
        var upperHighlight: SIMD3<Double>
        var lowerDeep: SIMD3<Double>
        var lowerBright: SIMD3<Double>
        var lowerMid: SIMD3<Double>
        var lowerHighlight: SIMD3<Double>
        var coreTint: SIMD3<Double>
        var idlePrimary: SIMD3<Double>
        var idleSecondary: SIMD3<Double>

        /// Seven-stop closed-loop spectrum (first == last) for thinking & waiting.
        var ringStops: [SIMD3<Double>] {
            [
                lowerBright,
                lowerMid,
                lowerHighlight,
                upperHighlight,
                upperMid,
                upperDeep,
                lowerBright
            ]
        }
    }

    var palette: Palette {
        switch self {
        case .prisma:
            return Palette(
                upperDeep: SIMD3(0.88, 0.30, 0.12),
                upperBright: SIMD3(1.00, 0.46, 0.12),
                upperMid: SIMD3(1.00, 0.66, 0.24),
                upperHighlight: SIMD3(1.00, 0.96, 0.84),
                lowerDeep: SIMD3(0.18, 0.44, 0.92),
                lowerBright: SIMD3(0.18, 0.62, 1.00),
                lowerMid: SIMD3(0.35, 0.95, 1.00),
                lowerHighlight: SIMD3(0.90, 0.97, 1.00),
                coreTint: SIMD3(1.00, 0.94, 0.72),
                idlePrimary: SIMD3(0.24, 0.61, 0.94),
                idleSecondary: SIMD3(0.05, 0.23, 0.56)
            )
        case .aurora:
            return Palette(
                upperDeep: SIMD3(0.62, 0.20, 0.96),
                upperBright: SIMD3(0.82, 0.36, 1.00),
                upperMid: SIMD3(0.95, 0.48, 0.92),
                upperHighlight: SIMD3(0.96, 0.88, 1.00),
                lowerDeep: SIMD3(0.06, 0.64, 0.50),
                lowerBright: SIMD3(0.12, 0.86, 0.66),
                lowerMid: SIMD3(0.36, 1.00, 0.82),
                lowerHighlight: SIMD3(0.86, 1.00, 0.95),
                coreTint: SIMD3(0.84, 1.00, 0.92),
                idlePrimary: SIMD3(0.14, 0.84, 0.66),
                idleSecondary: SIMD3(0.30, 0.12, 0.58)
            )
        case .oceano:
            return Palette(
                upperDeep: SIMD3(0.18, 0.28, 0.95),
                upperBright: SIMD3(0.32, 0.50, 1.00),
                upperMid: SIMD3(0.28, 0.70, 1.00),
                upperHighlight: SIMD3(0.84, 0.94, 1.00),
                lowerDeep: SIMD3(0.04, 0.64, 0.82),
                lowerBright: SIMD3(0.10, 0.84, 0.96),
                lowerMid: SIMD3(0.36, 0.98, 0.96),
                lowerHighlight: SIMD3(0.88, 1.00, 1.00),
                coreTint: SIMD3(0.80, 0.98, 1.00),
                idlePrimary: SIMD3(0.12, 0.78, 0.94),
                idleSecondary: SIMD3(0.06, 0.20, 0.62)
            )
        case .nebula:
            return Palette(
                upperDeep: SIMD3(0.92, 0.12, 0.56),
                upperBright: SIMD3(1.00, 0.24, 0.72),
                upperMid: SIMD3(1.00, 0.50, 0.86),
                upperHighlight: SIMD3(1.00, 0.88, 0.97),
                lowerDeep: SIMD3(0.26, 0.34, 0.96),
                lowerBright: SIMD3(0.20, 0.70, 1.00),
                lowerMid: SIMD3(0.28, 0.95, 1.00),
                lowerHighlight: SIMD3(0.88, 0.98, 1.00),
                coreTint: SIMD3(0.98, 0.88, 1.00),
                idlePrimary: SIMD3(0.84, 0.22, 0.74),
                idleSecondary: SIMD3(0.14, 0.32, 0.72)
            )
        case .solar:
            return Palette(
                upperDeep: SIMD3(0.86, 0.12, 0.16),
                upperBright: SIMD3(1.00, 0.28, 0.14),
                upperMid: SIMD3(1.00, 0.54, 0.12),
                upperHighlight: SIMD3(1.00, 0.92, 0.76),
                lowerDeep: SIMD3(0.92, 0.48, 0.08),
                lowerBright: SIMD3(1.00, 0.68, 0.16),
                lowerMid: SIMD3(1.00, 0.86, 0.36),
                lowerHighlight: SIMD3(1.00, 0.97, 0.84),
                coreTint: SIMD3(1.00, 0.94, 0.70),
                idlePrimary: SIMD3(0.96, 0.52, 0.16),
                idleSecondary: SIMD3(0.58, 0.12, 0.08)
            )
        case .amatista:
            return Palette(
                upperDeep: SIMD3(0.90, 0.28, 0.60),
                upperBright: SIMD3(1.00, 0.46, 0.76),
                upperMid: SIMD3(1.00, 0.66, 0.88),
                upperHighlight: SIMD3(1.00, 0.92, 0.97),
                lowerDeep: SIMD3(0.44, 0.18, 0.88),
                lowerBright: SIMD3(0.62, 0.34, 1.00),
                lowerMid: SIMD3(0.78, 0.58, 1.00),
                lowerHighlight: SIMD3(0.93, 0.88, 1.00),
                coreTint: SIMD3(0.96, 0.88, 1.00),
                idlePrimary: SIMD3(0.64, 0.34, 0.94),
                idleSecondary: SIMD3(0.30, 0.10, 0.56)
            )
        case .esmeralda:
            return Palette(
                upperDeep: SIMD3(0.86, 0.60, 0.10),
                upperBright: SIMD3(1.00, 0.78, 0.20),
                upperMid: SIMD3(0.84, 0.94, 0.30),
                upperHighlight: SIMD3(0.96, 1.00, 0.82),
                lowerDeep: SIMD3(0.05, 0.58, 0.34),
                lowerBright: SIMD3(0.12, 0.82, 0.46),
                lowerMid: SIMD3(0.34, 0.98, 0.62),
                lowerHighlight: SIMD3(0.86, 1.00, 0.90),
                coreTint: SIMD3(0.90, 1.00, 0.78),
                idlePrimary: SIMD3(0.18, 0.82, 0.48),
                idleSecondary: SIMD3(0.06, 0.36, 0.22)
            )
        case .artico:
            return Palette(
                upperDeep: SIMD3(0.48, 0.64, 0.86),
                upperBright: SIMD3(0.68, 0.82, 0.98),
                upperMid: SIMD3(0.82, 0.92, 1.00),
                upperHighlight: SIMD3(0.96, 0.99, 1.00),
                lowerDeep: SIMD3(0.18, 0.50, 0.92),
                lowerBright: SIMD3(0.32, 0.74, 1.00),
                lowerMid: SIMD3(0.58, 0.92, 1.00),
                lowerHighlight: SIMD3(0.92, 0.98, 1.00),
                coreTint: SIMD3(0.90, 0.97, 1.00),
                idlePrimary: SIMD3(0.42, 0.76, 0.98),
                idleSecondary: SIMD3(0.14, 0.32, 0.60)
            )
        case .atardecer:
            return Palette(
                upperDeep: SIMD3(0.94, 0.24, 0.30),
                upperBright: SIMD3(1.00, 0.42, 0.36),
                upperMid: SIMD3(1.00, 0.66, 0.42),
                upperHighlight: SIMD3(1.00, 0.90, 0.82),
                lowerDeep: SIMD3(0.32, 0.20, 0.84),
                lowerBright: SIMD3(0.50, 0.34, 0.96),
                lowerMid: SIMD3(0.68, 0.52, 1.00),
                lowerHighlight: SIMD3(0.90, 0.84, 1.00),
                coreTint: SIMD3(1.00, 0.90, 0.82),
                idlePrimary: SIMD3(0.88, 0.38, 0.52),
                idleSecondary: SIMD3(0.26, 0.14, 0.58)
            )
        case .platino:
            return Palette(
                upperDeep: SIMD3(0.72, 0.68, 0.62),
                upperBright: SIMD3(0.88, 0.84, 0.78),
                upperMid: SIMD3(0.94, 0.91, 0.85),
                upperHighlight: SIMD3(1.00, 0.99, 0.96),
                lowerDeep: SIMD3(0.50, 0.58, 0.72),
                lowerBright: SIMD3(0.68, 0.76, 0.88),
                lowerMid: SIMD3(0.82, 0.88, 0.96),
                lowerHighlight: SIMD3(0.96, 0.98, 1.00),
                coreTint: SIMD3(0.98, 0.98, 0.95),
                idlePrimary: SIMD3(0.68, 0.74, 0.86),
                idleSecondary: SIMD3(0.28, 0.32, 0.42)
            )
        }
    }
}

/// Everything the orb needs to draw one instant of its animation.
struct OrbFrame {
    var time: Double
    /// Pose weights of the voice horizon, the thinking ring and the waiting
    /// fold. They always add up to one.
    var voice: Double
    var thinking: Double
    var idle: Double
    /// Eases the voice energy between resting and talking.
    var speaking: Double
    /// Audio level smoothed every frame; the meter only updates at 30 Hz.
    var audio: Double
    /// Accumulated phases. A new state changes how fast they advance, never
    /// their value, so the light keeps travelling instead of jumping.
    var spin: Double
    var sweep: Double
    var idlePhase: Double
    /// Visual scale of the orb container (smaller while waiting, full size when active).
    var scale: Double = OverlayModel.activeScale
    /// Overall opacity of the orb so the desktop and windows behind it remain visible.
    var opacity: Double = OverlayModel.activeOpacity
    /// Selected color theme for the halo across all states.
    var theme: HaloTheme = .prisma
    /// 0...1 progress of the hover info capsule emerging from the orb.
    var hover: Double = 0
}

/// Quintic Hermite blend. Retargeting keeps value, velocity and acceleration
/// continuous, so an interrupted transition bends into the next one.
struct SmoothBlend<Value: SIMD> where Value.Scalar == Double {
    private var from: Value
    private var velocity = Value()
    private var acceleration = Value()
    private(set) var target: Value
    private var start: Double = 0
    private var duration: Double = 1
    /// Weights must stay within 0...1; positions are free.
    private let bounded: Bool

    init(_ value: Value, bounded: Bool = true) {
        from = value
        target = value
        self.bounded = bounded
    }

    private static func basis(_ t: Double) -> (h0: Double, h1: Double, h2: Double, h5: Double) {
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t, t5 = t4 * t
        return (
            1 - 10 * t3 + 15 * t4 - 6 * t5,
            t - 6 * t3 + 8 * t4 - 3 * t5,
            0.5 * t2 - 1.5 * t3 + 1.5 * t4 - 0.5 * t5,
            10 * t3 - 15 * t4 + 6 * t5
        )
    }

    func sample(at time: Double) -> (value: Value, velocity: Value, acceleration: Value) {
        let d = duration
        let t = min(1, max(0, (time - start) / d))
        guard t < 1 else { return (target, Value(), Value()) }
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t
        let (h0, h1, h2, h5) = Self.basis(t)

        let v0 = -30 * t2 + 60 * t3 - 30 * t4
        let v1 = 1 - 18 * t2 + 32 * t3 - 15 * t4
        let v2 = t - 4.5 * t2 + 6 * t3 - 2.5 * t4
        let v5 = 30 * t2 - 60 * t3 + 30 * t4

        let a0 = -60 * t + 180 * t2 - 120 * t3
        let a1 = -36 * t + 96 * t2 - 60 * t3
        let a2 = 1 - 9 * t + 18 * t2 - 10 * t3
        let a5 = 60 * t - 180 * t2 + 120 * t3

        let scaledVelocity = velocity * d
        let scaledAcceleration = acceleration * (d * d)
        let value = from * h0 + scaledVelocity * h1 + scaledAcceleration * h2 + target * h5
        let speed = (from * v0 + scaledVelocity * v1 + scaledAcceleration * v2 + target * v5) / d
        let accel = (from * a0 + scaledVelocity * a1 + scaledAcceleration * a2 + target * a5) / (d * d)
        return (value, speed, accel)
    }

    mutating func retarget(to newTarget: Value, at time: Double, duration newDuration: Double) {
        let current = sample(at: time)
        from = current.value
        velocity = current.velocity
        acceleration = current.acceleration
        target = newTarget
        start = time
        duration = max(0.001, newDuration)
        guard bounded else { return }
        // Keep the momentum, unless it would carry a weight outside 0...1.
        // Only an abrupt reversal of direction ever needs this.
        let limit = momentumLimit()
        velocity *= limit
        acceleration *= limit
    }

    private func momentumLimit() -> Double {
        var limit = 1.0
        let d = duration
        for k in 1...32 {
            let (h0, h1, h2, h5) = Self.basis(Double(k) / 32)
            let base = from * h0 + target * h5
            let push = velocity * (d * h1) + acceleration * (d * d * h2)
            for lane in 0..<Value.scalarCount {
                let b = base[lane], p = push[lane]
                if p < 0, b + p < 0 { limit = min(limit, max(0, b / -p)) }
                if p > 0, b + p > 1 { limit = min(limit, max(0, (1 - b) / p)) }
            }
        }
        return limit
    }

    mutating func snap(to value: Value, at time: Double) {
        from = value
        target = value
        velocity = Value()
        acceleration = Value()
        start = time
    }
}

/// Phases and levels that are integrated frame by frame.
struct OrbMotion {
    private var lastTime: Double?
    private(set) var spin = 0.0
    private(set) var sweep = 0.0
    private(set) var audio = 0.0

    mutating func advance(to time: Double, pose: SIMD3<Double>, audioTarget: Double) {
        guard let last = lastTime else {
            lastTime = time
            return
        }
        guard time > last else { return }
        let dt = min(time - last, 0.1)
        lastTime = time
        // Colours circle faster while thinking and drift slowly while waiting.
        spin += dt * (0.03 * pose.x + 0.1035 * pose.y + 0.038 * pose.z)
        sweep += dt * (0.75 * pose.x + 1.40 * pose.y + 0.75 * pose.z)
        let rate = audioTarget > audio ? 24.0 : 9.0
        audio += (audioTarget - audio) * (1 - exp(-rate * dt))
    }
}

final class OverlayModel: ObservableObject {
    static let inactiveScale: Double = 0.34
    static let activeScale: Double = 0.50
    static let inactiveOpacity: Double = 0.50
    static let activeOpacity: Double = 0.95

    @Published var visible = false
    @Published var isSpeaking = false {
        didSet { if oldValue != isSpeaking { stateChanged() } }
    }
    @Published var isThinking = false {
        didSet { if oldValue != isThinking { stateChanged() } }
    }
    @Published var hasIdleState = false {
        didSet { if oldValue != hasIdleState { stateChanged() } }
    }
    @Published var isHovered = false {
        didSet { if oldValue != isHovered { stateChanged() } }
    }
    @Published var showHoverInfo = true {
        didSet { if oldValue != showHoverInfo { stateChanged() } }
    }
    @Published var agentTitle: String = ""
    @Published var sessionTitle: String = ""
    /// Read by the animation timeline on every frame. Not published, so the
    /// 30 Hz meter does not add redraws between the evenly spaced frames.
    var audioLevel: Double = 0
    @Published var progress: Double = 0
    @Published var caption: String = "PRISMA"
    @Published var position: OverlayPosition = .top
    @Published var haloTheme: HaloTheme = .prisma
    /// True while the light changes shape, so it is drawn at 60 fps.
    @Published private(set) var isMorphing = false
    var idlePhase: Double = 0
    var clock: () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    var onActiveChange: (() -> Void)?

    var transitionFrom: Double = 0.0
    var transitionTo: Double = 0.0
    var transitionStartTime: TimeInterval = 0
    var transitionDuration: TimeInterval = 0.82

    private var pose = SmoothBlend(SIMD3<Double>(1, 0, 0))
    private var talking = SmoothBlend(SIMD2<Double>(0, 0))
    private var activity = SmoothBlend(SIMD2<Double>(1, 0))
    private var hoverBadge = SmoothBlend(SIMD2<Double>(0, 0))
    private var lastActive = true
    private var motion = OrbMotion()
    private var morphGeneration = 0
    private var morphingUntil: TimeInterval = 0
    /// Window origin while the orb slides to a new place in the row.
    private var glide = SmoothBlend(SIMD2<Double>(0, 0), bounded: false)
    private var glideEnd: TimeInterval = -.infinity

    /// Session orbs shrink while waiting unless they are thinking, speaking or hovered.
    var isActive: Bool {
        !hasIdleState || isThinking || isSpeaking || isHovered
    }

    /// Thinking wins over speaking; between turns the orb waits if it can.
    private var targetPose: SIMD3<Double> {
        if isThinking { return SIMD3(0, 1, 0) }
        if isSpeaking { return SIMD3(1, 0, 0) }
        return hasIdleState ? SIMD3(0, 0, 1) : SIMD3(1, 0, 0)
    }

    private func stateChanged() {
        let now = clock()
        let pose = targetPose
        let talk = SIMD2<Double>(isSpeaking ? 1 : 0, 0)
        let activeNow = isActive
        let active = SIMD2<Double>(activeNow ? 1 : 0, 0)
        let hoverTarget = SIMD2<Double>((isHovered && showHoverInfo) ? 1 : 0, 0)
        let activeChanged = activeNow != lastActive
        lastActive = activeNow
        guard visible else {
            // A hidden orb appears directly in its current shape and size.
            self.pose.snap(to: pose, at: now)
            talking.snap(to: talk, at: now)
            activity.snap(to: active, at: now)
            hoverBadge.snap(to: hoverTarget, at: now)
            if activeChanged { onActiveChange?() }
            return
        }
        if pose != self.pose.target {
            let duration = pose.y > 0.5 ? 1.15 : (pose.z > 0.5 ? 1.4 : 1.05)
            self.pose.retarget(to: pose, at: now, duration: duration)
            markMorphing(for: duration)
        }
        if talk != talking.target {
            talking.retarget(to: talk, at: now, duration: 0.45)
        }
        if active != activity.target {
            let duration = activeNow ? 0.45 : 0.58
            activity.retarget(to: active, at: now, duration: duration)
            markMorphing(for: duration)
        }
        if hoverTarget != hoverBadge.target {
            let duration = hoverTarget.x > 0.5 ? 0.46 : 0.36
            hoverBadge.retarget(to: hoverTarget, at: now, duration: duration)
            markMorphing(for: duration)
        }
        if activeChanged {
            onActiveChange?()
        }
    }

    /// Keeps the timeline at 60 fps for at least `duration`, without cutting
    /// short a longer animation that is already running.
    private func markMorphing(for duration: TimeInterval) {
        let until = clock() + duration
        guard until > morphingUntil || !isMorphing else { return }
        morphingUntil = until
        morphGeneration += 1
        let generation = morphGeneration
        if !isMorphing { isMorphing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { [weak self] in
            guard let self, self.morphGeneration == generation else { return }
            self.isMorphing = false
        }
    }

    // MARK: Sliding along the row

    /// Starts or redirects a slide of the window origin. A slide in progress
    /// keeps its momentum; a new one can wait `delay` seconds before moving.
    /// Only the window moves, so the light inside keeps its own pace.
    func glide(from origin: SIMD2<Double>, to target: SIMD2<Double>, delay: TimeInterval, duration: TimeInterval) {
        let now = clock()
        if now >= glideEnd {
            glide.snap(to: origin, at: now)
            glide.retarget(to: target, at: now + delay, duration: duration)
            glideEnd = now + delay + duration
        } else if target != glide.target {
            glide.retarget(to: target, at: now, duration: duration)
            glideEnd = now + duration
        }
    }

    func glidePosition(at time: TimeInterval) -> SIMD2<Double> {
        glide.sample(at: time).value
    }

    func isGliding(at time: TimeInterval) -> Bool {
        time < glideEnd
    }

    func endGlide() {
        glideEnd = -.infinity
    }

    func currentScale(at time: TimeInterval) -> Double {
        let active = min(1, max(0, activity.sample(at: time).value.x))
        return Self.inactiveScale + (Self.activeScale - Self.inactiveScale) * active
    }

    func currentOpacity(at time: TimeInterval) -> Double {
        let active = min(1, max(0, activity.sample(at: time).value.x))
        return Self.inactiveOpacity + (Self.activeOpacity - Self.inactiveOpacity) * active
    }

    func frame(at time: TimeInterval) -> OrbFrame {
        var weights = pose.sample(at: time).value
        weights = SIMD3(max(0, weights.x), max(0, weights.y), max(0, weights.z))
        let total = max(1e-6, weights.x + weights.y + weights.z)
        weights /= total
        let speaking = min(1, max(0, talking.sample(at: time).value.x))
        let hover = min(1, max(0, hoverBadge.sample(at: time).value.x))
        motion.advance(to: time, pose: weights, audioTarget: isSpeaking ? audioLevel : 0)
        return OrbFrame(
            time: time,
            voice: weights.x,
            thinking: weights.y,
            idle: weights.z,
            speaking: speaking,
            audio: motion.audio,
            spin: motion.spin,
            sweep: motion.sweep,
            idlePhase: idlePhase,
            scale: currentScale(at: time),
            opacity: currentOpacity(at: time),
            theme: haloTheme,
            hover: hover
        )
    }

    func currentPresentation(at now: TimeInterval) -> Double {
        guard transitionDuration > 0 else { return transitionTo }
        let u = min(1.0, max(0.0, (now - transitionStartTime) / transitionDuration))
        // A reversible timeline keeps size and shape continuous if the bubble
        // is shown again while it is still retracting.
        let eased = u * u * (3.0 - 2.0 * u)
        return transitionFrom + (transitionTo - transitionFrom) * eased
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat
    var alpha: CGFloat = 0.45

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = MaskedVisualEffectView()
        view.cornerRadius = cornerRadius
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        view.alphaValue = alpha
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // Called on every animation frame: only touch what actually changed.
        if let masked = nsView as? MaskedVisualEffectView {
            masked.cornerRadius = cornerRadius
        }
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
        if nsView.state != .active { nsView.state = .active }
        if abs(nsView.alphaValue - alpha) > 0.01 { nsView.alphaValue = alpha }
    }
}

final class MaskedVisualEffectView: NSVisualEffectView {
    var cornerRadius: CGFloat = 96 {
        didSet {
            guard cornerRadius != oldValue else { return }
            maskSize = .zero
            needsLayout = true
        }
    }
    private var maskSize: CGSize = .zero

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, bounds.size != maskSize else { return }
        let size = bounds.size
        maskSize = size
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(
                roundedRect: rect,
                xRadius: self.cornerRadius,
                yRadius: self.cornerRadius
            )
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsetsZero
        self.maskImage = image
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    /// 60 fps while the light moves and 30 fps while it only drifts, on both
    /// 60 Hz and 120 Hz displays. The intervals sit between frame periods on
    /// purpose: with exactly 1/60 s, display jitter skips about every other frame.
    private var minimumFrameInterval: Double {
        model.isThinking || model.isSpeaking || model.isMorphing ? 1.0 / 90.0 : 1.0 / 36.0
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: minimumFrameInterval, paused: !model.visible)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let presentation = model.currentPresentation(at: time)
            let slide = edgeTransform(for: model.position, presentation: presentation)
            let frame = model.frame(at: time)

            ZStack {
                if frame.hover > 0.002 && !model.agentTitle.isEmpty {
                    OrbInfoBadgeView(
                        agentTitle: model.agentTitle,
                        sessionTitle: model.sessionTitle,
                        theme: frame.theme,
                        position: model.position,
                        orbScale: CGFloat(frame.scale),
                        hover: CGFloat(frame.hover)
                    )
                }

                SiriLiquidGlassOrbView(frame: frame)
                    .accessibilityLabel(model.isThinking ? "Prisma está pensando" : "Prisma")
                    .scaleEffect(frame.scale, anchor: slide.anchor)
                    .scaleEffect(
                        x: slide.scaleX,
                        y: slide.scaleY,
                        anchor: slide.anchor
                    )
                    .offset(x: slide.offsetX, y: slide.offsetY)
            }
            .frame(width: 460, height: 360)
            .clipped()
            .opacity(model.visible ? frame.opacity * min(1, presentation * 12) : 0)
        }
    }

    private func edgeTransform(
        for position: OverlayPosition,
        presentation: Double
    ) -> (offsetX: CGFloat, offsetY: CGFloat, scaleX: CGFloat, scaleY: CGFloat, anchor: UnitPoint) {
        let p = CGFloat(min(max(presentation, 0), 1))
        let inv = 1.0 - p

        // Grow from a tiny droplet, gently overshoot, then settle into a circle.
        // Following the same curve backwards gives the exit its liquid pinch.
        let growth = 1.0 + 2.5 * pow(p - 1, 3) + 1.5 * pow(p - 1, 2)
        let size = 0.025 + 0.975 * growth
        let stretch = 0.28 * sin(p * .pi * 2) * pow(inv, 0.65)
        let sx = size * (1.0 - stretch * 0.65)
        let sy = size * (1.0 + stretch)

        switch position {
        case .top:
            // The small droplet starts just outside the edge so its growth is visible.
            let y: CGFloat = -26.0 - inv * 68.0
            return (0, y, sx, sy, .top)

        case .left:
            let x: CGFloat = -111.0 - inv * 34.0
            return (x, 0, sy, sx, .leading)

        case .right:
            let x: CGFloat = 111.0 + inv * 34.0
            return (x, 0, sy, sx, .trailing)

        case .bottom:
            let y: CGFloat = 52.0 + inv * 32.0
            return (0, y, sx, sy, .bottom)

        case .corner:
            let x: CGFloat = 42.0 + inv * 92.0
            let y: CGFloat = 52.0 + inv * 32.0
            return (x, y, sx, sy, .bottomTrailing)

        case .center:
            let y: CGFloat = -inv * 12.0
            return (0, y, sx, sy, .top)
        }
    }
}

/// Liquid-glass chip fused directly to the orb container while hovered,
/// showing the session title on top and the agent name below, left-aligned
/// in a Consolas-style monospaced font.
struct OrbInfoBadgeView: View {
    let agentTitle: String
    let sessionTitle: String
    let theme: HaloTheme
    let position: OverlayPosition
    let orbScale: CGFloat
    let hover: CGFloat

    private static func monoFont(size: CGFloat, weight: Font.Weight) -> Font {
        if NSFont(name: "Consolas", size: size) != nil {
            return .custom("Consolas", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    var body: some View {
        let p = min(1, max(0, hover))
        let inv = 1.0 - p
        let r = 99.0 * orbScale
        let stretch = 0.12 * sin(p * .pi) * pow(inv, 0.5)
        let grow = 0.08 + 0.92 * p
        let cross = 0.72 + 0.28 * p

        switch position {
        case .left:
            chipCard(edgeInset: .init(top: 8, leading: 36, bottom: 8, trailing: 15))
                .scaleEffect(
                    x: grow * (1.0 + stretch),
                    y: cross,
                    anchor: .leading
                )
                .opacity(Double(min(1, p * 1.4)))
                .padding(.leading, max(0, 20 + 2 * r - 22))
                .frame(width: 460, height: 360, alignment: .leading)

        case .right:
            chipCard(edgeInset: .init(top: 8, leading: 15, bottom: 8, trailing: 36))
                .scaleEffect(
                    x: grow * (1.0 + stretch),
                    y: cross,
                    anchor: .trailing
                )
                .opacity(Double(min(1, p * 1.4)))
                .padding(.trailing, max(0, 20 + 2 * r - 22))
                .frame(width: 460, height: 360, alignment: .trailing)

        case .bottom:
            chipCard(edgeInset: .init(top: 10, leading: 14, bottom: 30, trailing: 14))
                .scaleEffect(
                    x: cross,
                    y: grow * (1.0 + stretch),
                    anchor: .bottom
                )
                .opacity(Double(min(1, p * 1.4)))
                .padding(.bottom, max(0, 29 + 2 * r - 16))
                .frame(width: 460, height: 360, alignment: .bottom)

        case .corner:
            chipCard(edgeInset: .init(top: 10, leading: 14, bottom: 30, trailing: 14))
                .scaleEffect(
                    x: cross,
                    y: grow * (1.0 + stretch),
                    anchor: .bottom
                )
                .opacity(Double(min(1, p * 1.4)))
                .offset(x: 141 - r - 18)
                .padding(.bottom, max(0, 29 + 2 * r - 16))
                .frame(width: 460, height: 360, alignment: .bottom)

        case .center:
            chipCard(edgeInset: .init(top: 30, leading: 14, bottom: 10, trailing: 14))
                .scaleEffect(
                    x: cross,
                    y: grow * (1.0 + stretch),
                    anchor: .top
                )
                .opacity(Double(min(1, p * 1.4)))
                .padding(.top, max(0, 81 + 2 * r - 16))
                .frame(width: 460, height: 360, alignment: .top)

        case .top:
            chipCard(edgeInset: .init(top: 30, leading: 14, bottom: 10, trailing: 14))
                .scaleEffect(
                    x: cross,
                    y: grow * (1.0 + stretch),
                    anchor: .top
                )
                .opacity(Double(min(1, p * 1.4)))
                .padding(.top, max(0, 55 + 2 * r - 16))
                .frame(width: 460, height: 360, alignment: .top)
        }
    }

    private func chipCard(edgeInset: EdgeInsets) -> some View {
        let pal = theme.palette
        let accent = Color(red: pal.lowerMid.x, green: pal.lowerMid.y, blue: pal.lowerMid.z)
        let warm = Color(red: pal.upperBright.x, green: pal.upperBright.y, blue: pal.upperBright.z)
        let displayTitle = sessionTitle.isEmpty ? "Sesión activa" : sessionTitle
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)

        return VStack(alignment: .leading, spacing: 3) {
            Text(displayTitle)
                .font(Self.monoFont(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.96))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 5) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [warm, accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 6, height: 6)
                    .shadow(color: accent.opacity(0.85), radius: 3)

                Text(agentTitle)
                    .font(Self.monoFont(size: 10.0, weight: .medium))
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
        }
        .padding(edgeInset)
        .frame(maxWidth: 240, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            ZStack {
                shape
                    .fill(Color(red: 0.02, green: 0.03, blue: 0.06).opacity(0.92))

                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                warm.opacity(0.18),
                                accent.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            warm.opacity(0.62),
                            Color.white.opacity(0.50),
                            accent.opacity(0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 9, y: 4)
    }
}

enum OrbEnergy {
    /// Reactive energy: the voice meter while talking, a slow breath otherwise.
    static func value(for frame: OrbFrame) -> Double {
        let t = frame.time
        let resting = 0.05 * (0.5 + 0.5 * sin(t * 1.4))
        let talking = min(1.0, max(0.10 + 0.06 * sin(t * 3.8), frame.audio))
        let voice = resting + (talking - resting) * frame.speaking
        let thinking = 0.20 + 0.10 * sin(t * 1.65)
        let waiting = 0.16 + 0.06 * sin((t + frame.idlePhase) * 0.9)
        return voice * frame.voice + thinking * frame.thinking + waiting * frame.idle
    }
}

struct SiriLiquidGlassOrbView: View {
    let frame: OrbFrame

    private let orbWidth: CGFloat = 198
    private let orbHeight: CGFloat = 198
    private let cornerRadius: CGFloat = 99

    private var time: Double { frame.time }
    private var energy: Double { OrbEnergy.value(for: frame) }

    /// The light pulses with the voice. Only the light scales: resizing the
    /// glass would relayout its native blur on every frame.
    private var breathScale: CGFloat {
        1.0 + CGFloat(energy) * 0.020 + CGFloat(frame.thinking * sin(time * 1.65)) * 0.008
    }

    private var orbShape: Circle {
        Circle()
    }

    var body: some View {
        let energy = self.energy
        // Layers of a pose with no weight leave the tree, so a waiting orb
        // only redraws its light on each frame. They are invisible when they
        // come and go, so nothing pops.
        let showsVoice = frame.voice > 0.001
        let showsIdle = frame.idle > 0.001
        let tau = time + frame.idlePhase
        let pal = frame.theme.palette
        ZStack {
            // 1. Unclipped Gaussian drop shadow & subtle audio-reactive aura
            orbShape
                .fill(Color.black.opacity(0.24))
                .frame(width: orbWidth - 8, height: orbHeight - 8)
                .offset(y: 12)
                .blur(radius: 20)

            orbShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: pal.upperBright.x, green: pal.upperBright.y, blue: pal.upperBright.z).opacity(0.20),
                            Color(red: pal.lowerBright.x, green: pal.lowerBright.y, blue: pal.lowerBright.z).opacity(0.30)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: orbWidth - 12, height: orbHeight - 12)
                .blur(radius: 22)
                .opacity(0.3 + 0.7 * energy)

            // 2. Circular liquid glass shell shared by every state
            ZStack {
                // Foundation A: Real macOS backdrop blur masked to the circle
                VisualEffectBlur(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    cornerRadius: cornerRadius,
                    alpha: CGFloat(frame.opacity * 0.85)
                )

                if showsVoice {
                    // Foundation B: Translucent smoked glass below the voice horizon
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.14, green: 0.18, blue: 0.25).opacity(0.34), location: 0.00),
                            .init(color: Color(red: 0.26, green: 0.31, blue: 0.38).opacity(0.30), location: 0.52),
                            .init(color: Color(red: 0.44, green: 0.48, blue: 0.54).opacity(0.26), location: 0.78),
                            .init(color: Color(red: 0.76, green: 0.79, blue: 0.84).opacity(0.40), location: 1.00)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(frame.voice)

                    // Foundation C: Spherical inner glass glow in the lower hemisphere
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.25),
                            Color(red: pal.lowerMid.x, green: pal.lowerMid.y, blue: pal.lowerMid.z).opacity(0.16),
                            .clear
                        ],
                        center: UnitPoint(x: 0.5, y: 0.74),
                        startRadius: 4,
                        endRadius: 96
                    )
                    .opacity(frame.voice * (0.6 + 0.4 * energy))
                }

                // Foundation D: Translucent smoked interior. It covers the sky
                // above the voice horizon and closes over the lower glass as
                // the light curls into a ring, while letting the screen behind
                // the orb remain visible through the glass.
                RadialGradient(
                    stops: [
                        .init(color: Color(red: 0.01, green: 0.015, blue: 0.03).opacity(0.88), location: 0),
                        .init(color: Color(red: 0.02, green: 0.03, blue: 0.05).opacity(0.85), location: 0.60),
                        .init(color: Color(red: 0.055, green: 0.085, blue: 0.13).opacity(0.80), location: 0.88),
                        .init(color: Color(red: 0.09, green: 0.13, blue: 0.19).opacity(0.75), location: 1)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: orbHeight / 2
                )
                .mask {
                    ZStack {
                        Color.black.opacity(1 - frame.voice)
                        if showsVoice {
                            VoiceHorizonSky(frame: frame, energy: energy, color: .black)
                                .blur(radius: 8.0)
                        }
                    }
                }

                if showsVoice {
                    // Subtle night-sky tint above the voice horizon
                    VoiceHorizonSky(frame: frame, energy: energy, color: Color(red: 0.01, green: 0.01, blue: 0.02).opacity(0.22))
                        .blur(radius: 8.0)
                        .opacity(frame.voice)
                }

                if showsIdle {
                    // The ambient surface breathes behind the light while waiting.
                    RadialGradient(
                        colors: [Color(red: pal.idlePrimary.x, green: pal.idlePrimary.y, blue: pal.idlePrimary.z).opacity(0.58),
                                 Color(red: pal.idleSecondary.x, green: pal.idleSecondary.y, blue: pal.idleSecondary.z).opacity(0.32),
                                 .clear],
                        center: .center,
                        startRadius: 0, endRadius: 100
                    )
                    .frame(width: 200, height: 200)
                    .offset(x: orbWidth * 0.18 * sin(tau * 0.35), y: orbHeight * 0.12 * cos(tau * 0.30))
                    .opacity(frame.idle)
                    .blendMode(.screen)
                }

                // Foundation E: One beam of light for every state
                PrismaBeamView(frame: frame, energy: energy)
                    .frame(width: orbWidth, height: orbHeight)
                    .scaleEffect(breathScale)

                // Foundation F: Cylindrical 3D side glass curvature reflections
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            .white.opacity(0.24),
                            .white.opacity(0.04),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 42)

                    Spacer()

                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.04),
                            .white.opacity(0.20)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 42)
                }
                .blendMode(.overlay)

                if showsVoice {
                    // Foundation G: Bottom refractive caustics in the clear lower hemisphere
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        liquidGlassBottomRefraction(energy: energy)
                            .frame(height: 26)
                    }
                    .frame(width: orbWidth, height: orbHeight)
                    .opacity(frame.voice)
                }
            }
            .frame(width: orbWidth, height: orbHeight)
            .compositingGroup()
            .clipShape(orbShape)
            // Inner 3D optical glass rim bevel
            .overlay(
                orbShape
                    .inset(by: 1.5)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.04), location: 0.00),
                                .init(color: Color.white.opacity(0.16), location: 0.42),
                                .init(color: Color(red: 0.74, green: 0.88, blue: 1.0).opacity(0.36), location: 0.78),
                                .init(color: Color.white.opacity(0.62), location: 1.00)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.15
                    )
            )
            // Crisp outer specular Liquid Glass border
            .overlay(
                orbShape
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.42, green: 0.36, blue: 0.32).opacity(0.48), location: 0.00),
                                .init(color: Color.white.opacity(0.30), location: 0.30),
                                .init(color: Color.white.opacity(0.68), location: 0.65),
                                .init(color: Color.white.opacity(0.95), location: 1.00)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.35
                    )
            )
        }
    }

    // Refractive warped light caustics along the bottom glass curve
    private func liquidGlassBottomRefraction(energy: Double) -> some View {
        Canvas { context, size in
            guard frame.voice > 0.001 else { return }
            let w = size.width
            let h = size.height
            // Blend the two rhythms instead of switching frequency, which
            // would make the caustics jump when speech starts or stops.
            let slow = sin(time * 0.8)
            let fast = sin(time * 2.8)
            let shift = (slow + (fast - slow) * frame.speaking) * (4.0 + 5.0 * energy)

            var leftPath = Path()
            leftPath.move(to: CGPoint(x: w * 0.14, y: h * 0.15))
            leftPath.addQuadCurve(
                to: CGPoint(x: w * 0.36 + shift * 0.4, y: h * 0.78),
                control: CGPoint(x: w * 0.20, y: h * 0.72)
            )
            context.stroke(
                leftPath,
                with: .color(.white.opacity(0.30 + 0.12 * energy)),
                style: StrokeStyle(lineWidth: 2.8, lineCap: .round)
            )

            var centerPath = Path()
            centerPath.move(to: CGPoint(x: w * 0.38 - shift * 0.3, y: h * 0.82))
            centerPath.addQuadCurve(
                to: CGPoint(x: w * 0.68 + shift * 0.3, y: h * 0.76),
                control: CGPoint(x: w * 0.53, y: h * 0.96)
            )
            context.stroke(
                centerPath,
                with: .color(.white.opacity(0.46 + 0.18 * energy)),
                style: StrokeStyle(lineWidth: 3.4, lineCap: .round)
            )

            var rightPath = Path()
            rightPath.move(to: CGPoint(x: w * 0.72 - shift * 0.3, y: h * 0.70))
            rightPath.addQuadCurve(
                to: CGPoint(x: w * 0.86, y: h * 0.18),
                control: CGPoint(x: w * 0.81, y: h * 0.68)
            )
            context.stroke(
                rightPath,
                with: .color(.white.opacity(0.28 + 0.12 * energy)),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
            )
        }
        .blur(radius: 1.0)
        .blendMode(.screen)
    }
}

/// The dark sky above the voice horizon.
struct VoiceHorizonSky: View {
    let frame: OrbFrame
    let energy: Double
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard frame.voice > 0.001 else { return }
            let beam = PrismaBeam(frame: frame, energy: energy, size: size)
            context.fill(beam.skyPath(width: Double(size.width)), with: .color(color))
        }
    }
}

/// Bloom, spectral bands and the incandescent core of the beam.
struct PrismaBeamView: View {
    let frame: OrbFrame
    let energy: Double

    var body: some View {
        ZStack {
            // Wide atmospheric bloom (amber outside, sapphire inside), screened
            // with the spectral prism dispersion (red, gold, cyan, azure). One
            // canvas keeps the per-frame work small; screen is associative, so
            // it composes exactly like two screened layers.
            Canvas { context, size in
                let beam = PrismaBeam(frame: frame, energy: energy, size: size)

                var bloom = context
                bloom.addFilter(.blur(radius: 9.0 - 3.0 * frame.thinking))
                bloom.drawLayer { layer in
                    for band in beam.bloomBands { beam.draw(band, in: &layer) }
                }

                var spectrum = context
                spectrum.blendMode = .screen
                spectrum.addFilter(.blur(radius: 2.6 - 1.7 * frame.thinking))
                spectrum.drawLayer { layer in
                    for band in beam.spectralBands { beam.draw(band, in: &layer) }
                }
            }
            .blendMode(.screen)

            // Incandescent warm-white filament
            Canvas { context, size in
                let beam = PrismaBeam(frame: frame, energy: energy, size: size)
                beam.draw(beam.coreBand, in: &context)
            }
            .blur(radius: 1.2 - 0.7 * frame.thinking)
            .blendMode(.plusLighter)
        }
    }
}

/// A single beam of light. Its centre line is an arc whose total bend goes
/// from the gentle voice horizon to a closed loop for the thinking ring and
/// the waiting fold, so changing state bends the same light instead of
/// replacing it. Bands, thickness and colour are attached to the position
/// along the beam and travel with it while it curls.
struct PrismaBeam {
    struct Stop {
        var location: Double
        var color: SIMD4<Double>
    }

    struct Band {
        /// Offset from the core in the voice horizon; positive is below.
        /// While curled the same side faces the centre of the loop.
        var lift: Double
        /// Extra arch height of this band in the voice horizon.
        var arch: Double
        var thickness: Double
        var phase: Double
        /// Voice colours along the beam (0 is the left end).
        var stops: [Stop]
    }

    private static let outlineSamples = 72
    private static let colourStride = 4

    let frame: OrbFrame
    let energy: Double
    private let themePalette: HaloTheme.Palette
    private let ringStops: [SIMD3<Double>]
    private let center: SIMD2<Double>
    private let archHeight: Double
    private let length: Double
    private let kappa: Double
    private let apex: SIMD2<Double>
    private let curvatureCenter: SIMD2<Double>
    private let scale: SIMD2<Double>
    /// 1 while the light forms a closed loop, 0 on the open voice horizon.
    private let closure: Double
    /// How strongly the ends of an opening loop fade out.
    private let endFade: Double

    init(frame: OrbFrame, energy: Double, size: CGSize) {
        self.frame = frame
        self.energy = energy
        let pal = frame.theme.palette
        self.themePalette = pal
        self.ringStops = pal.ringStops
        center = SIMD2(Double(size.width) / 2, Double(size.height) / 2)
        archHeight = 15.0 + 7.5 * energy

        let wv = frame.voice, wt = frame.thinking, wi = frame.idle
        // The light first fades where the loop will part and only then opens,
        // so it retracts from the gap instead of being cut. Closing reverses
        // it: the faded ends meet before they light up again.
        let open = pow(max(0, wv - 0.1) / 0.9, 1.5)
        closure = 1 - open
        endFade = Self.smoothstep(0, 0.16, wv)

        let voiceLength = Double(size.width)
        let voiceTurn = 8 * archHeight / voiceLength
        let ringRadius = 41.34 * (1 + 0.035 * sin(frame.time * 1.5))
        let idleRadius = 60.44
        let closed = wt + wi
        let loopRadius = closed > 1e-6 ? (wt * ringRadius + wi * idleRadius) / closed : ringRadius
        let turn = open * voiceTurn + closure * 2 * Double.pi
        length = open * voiceLength + closure * 2 * Double.pi * loopRadius
        kappa = turn / length

        // Keep the arc's centroid in the middle of the glass while it curls;
        // the voice pose keeps its brightest point exactly at the centre.
        let lift = Self.apexToCentroid(turn: turn, length: length)
            - open * Self.apexToCentroid(turn: voiceTurn, length: voiceLength)
        apex = SIMD2(center.x, center.y - lift)
        curvatureCenter = SIMD2(apex.x, apex.y + 1 / kappa)

        let tau = frame.time + frame.idlePhase
        scale = SIMD2(
            wv + wt * 1.12 + wi * (1.04 + 0.04 * sin(tau * 0.4)),
            wv + wt * 0.92 + wi * 0.94
        )
    }

    private static func sinc(_ x: Double) -> Double {
        abs(x) < 1e-4 ? 1 - x * x / 6 : sin(x) / x
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// Loop light that fades towards the ends while the loop is open.
    private func loopFactor(at u: Double) -> Double {
        let fade = Self.smoothstep(0, 0.14, min(u, 1 - u))
        return 1 - endFade * (1 - fade)
    }

    private static func apexToCentroid(turn: Double, length: Double) -> Double {
        (1 - sinc(turn / 2)) * length / turn
    }

    // MARK: Bands

    private static func stop(_ location: Double, _ rgb: SIMD3<Double>, _ a: Double) -> Stop {
        Stop(location: location, color: SIMD4(rgb.x, rgb.y, rgb.z, a))
    }

    private static func clear(_ location: Double) -> Stop {
        Stop(location: location, color: SIMD4(0, 0, 0, 0))
    }

    var bloomBands: [Band] {
        let e = energy
        let spread = 1.0 + e * 1.15
        let p = themePalette
        return [
            // Lower bloom
            Band(lift: 10.0 * spread - 0.4, arch: -1.0, thickness: 22.0 + 20.0 * e, phase: 0.0, stops: [
                Self.clear(0.02),
                Self.stop(0.20, p.lowerDeep, 0.38 + 0.25 * e),
                Self.stop(0.50, p.lowerBright, 0.78 + 0.20 * e),
                Self.stop(0.80, p.lowerDeep, 0.38 + 0.25 * e),
                Self.clear(0.98)
            ]),
            // Upper bloom
            Band(lift: -5.5 * spread - 0.4, arch: 0.5, thickness: 13.0 + 12.0 * e, phase: 0.45, stops: [
                Self.clear(0.05),
                Self.stop(0.24, p.upperDeep, 0.45 + 0.25 * e),
                Self.stop(0.50, p.upperBright, 0.78 + 0.20 * e),
                Self.stop(0.76, p.upperDeep, 0.48 + 0.25 * e),
                Self.clear(0.95)
            ])
        ]
    }

    var spectralBands: [Band] {
        let e = energy
        let spread = 1.0 + e * 0.85
        let p = themePalette
        let lowerInnerPeak = p.lowerMid * 0.65 + p.lowerHighlight * 0.35
        let upperInnerPeak = p.upperMid * 0.55 + p.upperHighlight * 0.45
        return [
            // Upper outer arc
            Band(lift: -4.8 * spread - 0.4, arch: 0.6, thickness: 6.2 + 5.5 * e, phase: 0.25, stops: [
                Self.clear(0.06),
                Self.stop(0.24, p.upperDeep, 0.72 + 0.20 * e),
                Self.stop(0.50, p.upperBright, 0.96),
                Self.stop(0.76, p.upperDeep, 0.76 + 0.18 * e),
                Self.clear(0.94)
            ]),
            // Lower outer arc
            Band(lift: 6.6 * spread - 0.4, arch: -0.8, thickness: 8.5 + 7.5 * e, phase: -0.25, stops: [
                Self.clear(0.03),
                Self.stop(0.20, p.lowerDeep, 0.68 + 0.22 * e),
                Self.stop(0.50, p.lowerBright, 0.96),
                Self.stop(0.80, p.lowerDeep, 0.68 + 0.22 * e),
                Self.clear(0.97)
            ]),
            // Mid-lower arc
            Band(lift: 3.0 * spread - 0.4, arch: -0.3, thickness: 5.8 + 5.0 * e, phase: -0.10, stops: [
                Self.clear(0.08),
                Self.stop(0.26, p.lowerMid, 0.75 + 0.18 * e),
                Self.stop(0.50, lowerInnerPeak, 0.98),
                Self.stop(0.74, p.lowerMid, 0.75 + 0.18 * e),
                Self.clear(0.92)
            ]),
            // Mid-upper arc
            Band(lift: -1.8 * spread - 0.4, arch: 0.2, thickness: 5.0 + 4.5 * e, phase: 0.10, stops: [
                Self.clear(0.10),
                Self.stop(0.28, p.upperMid, 0.78 + 0.16 * e),
                Self.stop(0.50, upperInnerPeak, 0.98),
                Self.stop(0.72, p.upperMid, 0.80 + 0.16 * e),
                Self.clear(0.90)
            ])
        ]
    }

    var coreBand: Band {
        let e = energy
        let p = themePalette
        return Band(lift: 0, arch: 0, thickness: 3.4 + 4.2 * e, phase: 0, stops: [
            Self.clear(0.12),
            Self.stop(0.28, p.coreTint, 0.72 + 0.22 * e),
            Self.stop(0.50, SIMD3(1.0, 1.0, 0.98), 1.0),
            Self.stop(0.72, p.coreTint, 0.72 + 0.22 * e),
            Self.clear(0.88)
        ])
    }

    // MARK: Geometry

    /// The voice horizon of the core, followed by the dark sky above it.
    private func voiceHorizonY(_ u: Double) -> Double {
        let centred = 2 * u - 1
        let arch = max(0, 1 - centred * centred)
        let t = frame.time * 1.2
        let harmonics = 0.55 * sin(u * 6.2 - t) + 0.30 * sin(u * 12.4 + t * 1.35) + 0.15 * cos(u * 18.0 - t * 1.70)
        let wave = harmonics * (0.6 + 8.5 * energy) * pow(arch, 1.35)
        return center.y + archHeight * (1 - arch) + wave
    }

    func skyPath(width: Double) -> Path {
        let steps = 48
        let edge = 3.6
        var path = Path()
        path.move(to: CGPoint(x: -24, y: -24))
        path.addLine(to: CGPoint(x: width + 24, y: -24))
        path.addLine(to: CGPoint(x: width + 24, y: voiceHorizonY(1) + edge))
        for i in (0...steps).reversed() {
            let u = Double(i) / Double(steps)
            path.addLine(to: CGPoint(x: u * width, y: voiceHorizonY(u) + edge))
        }
        path.addLine(to: CGPoint(x: -24, y: voiceHorizonY(0) + edge))
        path.closeSubpath()
        return path
    }

    private static func voiceColour(_ stops: [Stop], at u: Double) -> SIMD4<Double> {
        guard let first = stops.first, let last = stops.last else { return SIMD4() }
        if u <= first.location { return first.color }
        if u >= last.location { return last.color }
        for i in 1..<stops.count where u <= stops[i].location {
            let a = stops[i - 1], b = stops[i]
            let f = (u - a.location) / max(1e-9, b.location - a.location)
            return a.color + (b.color - a.color) * f
        }
        return last.color
    }

    private func paletteColour(_ position: Double) -> SIMD3<Double> {
        let x = (position - floor(position)) * 6
        let i = min(5, Int(x))
        let f = x - Double(i)
        return ringStops[i] + (ringStops[i + 1] - ringStops[i]) * f
    }

    /// Colour of the beam at `u`, blended in premultiplied space so the
    /// light keeps its brightness while it changes palette.
    private func colour(_ band: Band, at u: Double) -> Color {
        let voice = Self.voiceColour(band.stops, at: u)
        let ring = paletteColour(u - frame.spin - frame.idlePhase * 0.16)
        let voiceAlpha = frame.voice * voice.w
        let loopAlpha = (frame.thinking + frame.idle * 0.28) * loopFactor(at: u)
        let alpha = voiceAlpha + loopAlpha
        guard alpha > 1e-5 else { return .clear }
        let rgb = (SIMD3(voice.x, voice.y, voice.z) * voiceAlpha + ring * loopAlpha) / alpha
        return Color(.sRGB, red: rgb.x, green: rgb.y, blue: rgb.z, opacity: min(1, alpha))
    }

    /// Outline of one band: its outer and inner edges, the centre line used to
    /// place colours, and the pivot of the conic gradient.
    struct Outline {
        var outer: [CGPoint]
        var inner: [CGPoint]
        var spine: [CGPoint]
        var pivot: CGPoint
    }

    func draw(_ band: Band, in context: inout GraphicsContext) {
        let shape = outline(band)
        let twoPi = 2 * Double.pi

        var path = Path()
        path.move(to: shape.outer[0])
        for point in shape.outer.dropFirst() { path.addLine(to: point) }
        for point in shape.inner.reversed() { path.addLine(to: point) }
        path.closeSubpath()

        // Colour follows the beam: a conic gradient around the centre of the
        // arc with one stop per sampled position along the light.
        let pivot = shape.pivot
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(shape.spine.count)
        var startAngle = 0.0
        var previous = 0.0
        var travelled = 0.0
        for (k, point) in shape.spine.enumerated() {
            let angle = atan2(Double(point.y - pivot.y), Double(point.x - pivot.x))
            if k == 0 {
                startAngle = angle
            } else {
                var step = angle - previous
                if step > .pi { step -= twoPi }
                if step < -.pi { step += twoPi }
                travelled += max(0, step)
            }
            previous = angle
            let u = Double(k * Self.colourStride) / Double(Self.outlineSamples)
            stops.append(Gradient.Stop(color: colour(band, at: u), location: min(1, travelled / twoPi)))
        }

        context.fill(
            path,
            with: .conicGradient(Gradient(stops: stops), center: pivot, angle: .radians(startAngle))
        )
    }

    func outline(_ band: Band) -> Outline {
        let wv = frame.voice, wt = frame.thinking, wi = frame.idle
        let t = frame.time
        let tau = t + frame.idlePhase
        let twoPi = 2 * Double.pi

        // Loop-only motion settles while the loop is open so the arc never wobbles.
        let loopMotion = closure * closure
        let tilt = wt * loopMotion * 0.12 * sin(t * 0.55 + band.phase * 2)
        let cosTilt = cos(tilt), sinTilt = sin(tilt)
        let sweepOffset = band.phase * (4 * (wv + wt) + 6 * wi)
        let warpBase = 0.25 * sin(tau * 0.22) + 0.5 * band.phase
        let waveTime = t * 1.2 + band.phase
        let waveAmplitude = 0.6 + 8.5 * energy
        let lift = band.lift
        let idleMotion = wi * loopMotion

        func place(_ p: SIMD2<Double>) -> CGPoint {
            let d = (p - center) * scale
            return CGPoint(x: center.x + d.x * cosTilt - d.y * sinTilt,
                           y: center.y + d.x * sinTilt + d.y * cosTilt)
        }

        let count = Self.outlineSamples
        var outer: [CGPoint] = []
        var inner: [CGPoint] = []
        var spine: [CGPoint] = []
        outer.reserveCapacity(count + 1)
        inner.reserveCapacity(count + 1)

        // Poses with no weight are skipped; usually only one is visible.
        let hasVoice = wv > 1e-5, hasRing = wt > 1e-5, hasIdle = wi > 1e-5
        let innerFold = 0.20 + 1.10 * loopMotion

        for i in 0...count {
            let u = Double(i) / Double(count)
            let theta = twoPi * u
            let centred = 2 * u - 1
            let arch = max(0, 1 - centred * centred)

            // The waiting fold lets the light slide gently along its loop.
            let warp = hasIdle ? idleMotion * (0.22 * sin(2 * theta + tau * 0.55) + warpBase) : 0
            let s = (u - 0.5 + warp / twoPi) * length
            let phi = kappa * s
            let half = Self.sinc(phi / 2)
            let base = SIMD2(apex.x + s * Self.sinc(phi), apex.y + s * phi * 0.5 * half * half)
            let normal = SIMD2(sin(phi), -cos(phi))

            // Offsets along the outward normal (up on the voice horizon) and
            // half thicknesses: a lens-shaped voice light, a travelling sweep
            // around the ring and broad asymmetric folds while waiting. The
            // soft inner glow of the fold only fills the loop once it closes.
            var offset = 0.0
            var shared = 0.0
            var fold = 0.0
            if hasVoice {
                let logArch = arch > 0 ? log(arch) : -.infinity
                let h1 = 0.55 * sin(u * 6.2 - waveTime)
                let h2 = 0.30 * sin(u * 12.4 + waveTime * 1.35)
                let h3 = 0.15 * cos(u * 18.0 - waveTime * 1.70)
                let wave = (h1 + h2 + h3) * waveAmplitude * exp(1.35 * logArch)
                offset += wv * (-lift + band.arch * arch - wave)
                let pulse = 1 + 0.28 * energy * sin(u * 9.0 + t * 7.0 + band.phase)
                shared += wv * band.thickness * 0.5 * exp(1.4 * logArch) * pulse
            }
            if hasRing || hasIdle {
                let sweep = 0.5 + 0.5 * sin(theta - frame.sweep + sweepOffset)
                let sweepSquared = sweep * sweep
                let loopEnds = loopFactor(at: u)
                if hasRing {
                    let ripple = 1.7 * sin(3 * theta + t * 1.15 + band.phase * 4) + 0.9 * sin(2 * theta - t * 0.8)
                    offset += wt * (-0.85 * lift + ripple * loopMotion)
                    shared += wt * band.thickness * 0.17 * (0.45 + 0.85 * sweepSquared) * loopEnds
                }
                if hasIdle {
                    let lobes = 8.0 * sin(2 * theta + tau * 0.62 + band.phase * 6) + 3.0 * sin(3 * theta - tau * 0.48)
                    offset += wi * (-1.1 * lift + lobes * loopMotion)
                    fold = wi * (7.0 + band.thickness * 0.45) * (0.40 + 1.70 * sweepSquared) * loopEnds
                }
            }
            let centre = base + normal * offset
            let outward = shared + 0.20 * fold
            let inward = shared + innerFold * fold

            outer.append(place(centre + normal * outward))
            inner.append(place(centre - normal * inward))
            if i % Self.colourStride == 0 { spine.append(place(centre)) }
        }

        return Outline(outer: outer, inner: inner, spine: spine, pivot: place(curvatureCenter))
    }
}
