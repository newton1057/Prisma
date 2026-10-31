import SwiftUI
import AppKit

final class OverlayModel: ObservableObject {
    @Published var visible = false
    @Published var isSpeaking = false
    @Published var audioLevel: Double = 0
    @Published var progress: Double = 0
    @Published var caption: String = "PRISMA"
    @Published var position: OverlayPosition = .top

    var transitionFrom: Double = 0.0
    var transitionTo: Double = 0.0
    var transitionStartTime: TimeInterval = 0
    var transitionDuration: TimeInterval = 0.48

    func currentPresentation(at now: TimeInterval) -> Double {
        guard transitionDuration > 0 else { return transitionTo }
        let u = min(1.0, max(0.0, (now - transitionStartTime) / transitionDuration))
        let eased: Double
        if transitionTo >= transitionFrom {
            // Smooth spring-like ease-out when emerging from the screen border
            eased = 1.0 - pow(1.0 - u, 3.3)
        } else {
            // Smooth ease-in-out retraction back into the screen border
            eased = u * u * (3.0 - 2.0 * u)
        }
        return transitionFrom + (transitionTo - transitionFrom) * eased
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = MaskedVisualEffectView()
        view.cornerRadius = cornerRadius
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if let masked = nsView as? MaskedVisualEffectView {
            masked.cornerRadius = cornerRadius
        }
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

final class MaskedVisualEffectView: NSVisualEffectView {
    var cornerRadius: CGFloat = 96 {
        didSet { needsLayout = true }
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let size = bounds.size
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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !model.visible)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let presentation = model.currentPresentation(at: time)
            let slide = edgeTransform(for: model.position, presentation: presentation)

            ZStack {
                SiriLiquidGlassOrbView(
                    time: time,
                    isSpeaking: model.isSpeaking,
                    audioLevel: model.audioLevel,
                    progress: model.progress
                )
                .scaleEffect(
                    x: slide.scaleX,
                    y: slide.scaleY,
                    anchor: slide.anchor
                )
                .offset(x: slide.offsetX, y: slide.offsetY)
            }
            .frame(width: 460, height: 360)
            .clipped()
            .opacity(model.visible ? 1 : 0)
        }
    }

    private func edgeTransform(
        for position: OverlayPosition,
        presentation: Double
    ) -> (offsetX: CGFloat, offsetY: CGFloat, scaleX: CGFloat, scaleY: CGFloat, anchor: UnitPoint) {
        let p = CGFloat(min(max(presentation, 0), 1))
        let inv = 1.0 - p

        switch position {
        case .top:
            // At p = 0: offsetY = -310 (completely tucked above the top border / Notch)
            // At p = 1: offsetY = -26 (top of orb sits at y = 55pt, cleanly below the 38pt MacBook Notch)
            let y: CGFloat = -26.0 - inv * 284.0
            let sx: CGFloat = 0.86 + 0.14 * p
            let sy: CGFloat = 0.66 + 0.34 * p
            return (0, y, sx, sy, .top)

        case .bottom:
            // At p = 0: offsetY = +310 (completely tucked below the bottom border of the screen)
            // At p = 1: offsetY = +52 (resting near the bottom border of the screen)
            let y: CGFloat = 52.0 + inv * 258.0
            let sx: CGFloat = 0.86 + 0.14 * p
            let sy: CGFloat = 0.66 + 0.34 * p
            return (0, y, sx, sy, .bottom)

        case .corner:
            // Slides out from and back into the bottom-right screen border
            let x: CGFloat = 42.0 + inv * 290.0
            let y: CGFloat = 52.0 + inv * 220.0
            let sx: CGFloat = 0.84 + 0.16 * p
            let sy: CGFloat = 0.84 + 0.16 * p
            return (x, y, sx, sy, .bottomTrailing)

        case .center:
            let y: CGFloat = -inv * 90.0
            let sx: CGFloat = 0.82 + 0.18 * p
            let sy: CGFloat = 0.82 + 0.18 * p
            return (0, y, sx, sy, .top)
        }
    }
}

struct SiriLiquidGlassOrbView: View {
    let time: Double
    let isSpeaking: Bool
    let audioLevel: Double
    let progress: Double

    private let orbWidth: CGFloat = 276
    private let orbHeight: CGFloat = 198
    private let cornerRadius: CGFloat = 96

    // Effective reactive energy combining real-time audio meter and subtle organic breathing
    private var energy: Double {
        if isSpeaking {
            let idleWave = 0.10 + 0.06 * sin(time * 3.8)
            return min(1.0, max(idleWave, audioLevel))
        } else {
            return 0.05 * (0.5 + 0.5 * sin(time * 1.4))
        }
    }

    private var breathScale: CGFloat {
        1.0 + CGFloat(energy) * 0.020
    }

    private var orbShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            // 1. Unclipped Gaussian drop shadow & subtle audio-reactive aura
            orbShape
                .fill(Color.black.opacity(0.42))
                .frame(width: orbWidth - 8, height: orbHeight - 8)
                .offset(y: 12)
                .blur(radius: 20)

            orbShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.48, blue: 0.18).opacity(0.06 + 0.14 * energy),
                            Color(red: 0.22, green: 0.64, blue: 1.00).opacity(0.10 + 0.20 * energy)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: orbWidth - 12, height: orbHeight - 12)
                .blur(radius: 22)

            // 2. Main 3D Liquid Glass Capsule-Orb (iOS 27 Siri AI style)
            ZStack {
                // Foundation A: Real macOS backdrop blur masked to the capsule shape
                VisualEffectBlur(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    cornerRadius: cornerRadius
                )

                // Foundation B: Translucent Smoked Liquid Glass base for the lower lens
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.14, green: 0.18, blue: 0.25).opacity(0.36), location: 0.00),
                        .init(color: Color(red: 0.26, green: 0.31, blue: 0.38).opacity(0.32), location: 0.52),
                        .init(color: Color(red: 0.44, green: 0.48, blue: 0.54).opacity(0.28), location: 0.78),
                        .init(color: Color(red: 0.76, green: 0.79, blue: 0.84).opacity(0.44), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Foundation C: Spherical inner glass glow in the lower hemisphere
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.15 + 0.10 * energy),
                        Color(red: 0.42, green: 0.74, blue: 1.0).opacity(0.08 + 0.08 * energy),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.74),
                    startRadius: 4,
                    endRadius: 96
                )

                // Foundation D: Unified Curved Obsidian Dome + Audio-Reactive Spectral Prism Horizon (`⌒`)
                SiriSpectralHorizonCanvas(
                    time: time,
                    isSpeaking: isSpeaking,
                    energy: energy
                )
                .frame(width: orbWidth, height: orbHeight)

                // Foundation E: Cylindrical 3D side glass curvature reflections
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

                // Foundation F: Lower glass hemisphere content ("PRISMA" + bottom refractive caustics)
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: orbHeight * 0.56)

                    Text("PRISMA")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.88),
                                    Color(white: 0.76).opacity(0.68)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)

                    Spacer(minLength: 4)

                    liquidGlassBottomRefraction
                        .frame(height: 26)
                }
                .frame(width: orbWidth, height: orbHeight)
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
            .scaleEffect(breathScale)
        }
    }

    // Refractive warped light caustics along the bottom glass curve
    private var liquidGlassBottomRefraction: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let shift = sin(time * (isSpeaking ? 2.8 : 0.8)) * (4.0 + 5.0 * energy)

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

/// Draws both the curved upper obsidian dome AND the audio-reactive spectral prism horizon (`⌒`)
/// along the exact same mathematical curve so there are zero straight horizontal seams.
struct SiriSpectralHorizonCanvas: View {
    let time: Double
    let isSpeaking: Bool
    let energy: Double

    var body: some View {
        ZStack {
            // 1. Curved Upper Obsidian Dome feathered purely via Gaussian blur on its curved bottom edge
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let eqY = h * 0.46
                let archHeight: CGFloat = 15.0 + CGFloat(energy) * 7.5

                let dome = upperDomePath(
                    width: w,
                    baseY: eqY + 3.0,
                    archHeight: archHeight,
                    time: time,
                    energy: energy
                )
                context.fill(
                    dome,
                    with: .color(Color(red: 0.01, green: 0.01, blue: 0.02))
                )
            }
            .blur(radius: 8.0)

            // 2. Wide Atmospheric Audio-Reactive Bloom (Amber above, Electric Cyan/Sapphire below)
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let eqY = h * 0.455
                let archHeight: CGFloat = 15.0 + CGFloat(energy) * 7.5
                let spread = 1.0 + energy * 1.15

                // Lower cyan/azure bloom
                let blueBloom = horizonRibbonPath(
                    width: w,
                    baseY: eqY + CGFloat(10.0 * spread),
                    archHeight: archHeight - 1.0,
                    thickness: CGFloat(22.0 + 20.0 * energy),
                    time: time,
                    energy: energy,
                    phaseOffset: 0.0
                )
                context.fill(
                    blueBloom,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0.02),
                            .init(color: Color(red: 0.18, green: 0.44, blue: 0.92).opacity(0.38 + 0.25 * energy), location: 0.20),
                            .init(color: Color(red: 0.26, green: 0.72, blue: 1.00).opacity(0.78 + 0.20 * energy), location: 0.50),
                            .init(color: Color(red: 0.18, green: 0.44, blue: 0.92).opacity(0.38 + 0.25 * energy), location: 0.80),
                            .init(color: .clear, location: 0.98)
                        ]),
                        startPoint: CGPoint(x: 0, y: eqY),
                        endPoint: CGPoint(x: w, y: eqY)
                    )
                )

                // Upper crimson/amber bloom
                let warmBloom = horizonRibbonPath(
                    width: w,
                    baseY: eqY - CGFloat(5.5 * spread),
                    archHeight: archHeight + 0.5,
                    thickness: CGFloat(13.0 + 12.0 * energy),
                    time: time,
                    energy: energy,
                    phaseOffset: 0.45
                )
                context.fill(
                    warmBloom,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0.05),
                            .init(color: Color(red: 0.72, green: 0.22, blue: 0.12).opacity(0.45 + 0.25 * energy), location: 0.24),
                            .init(color: Color(red: 0.98, green: 0.44, blue: 0.14).opacity(0.78 + 0.20 * energy), location: 0.50),
                            .init(color: Color(red: 0.78, green: 0.26, blue: 0.12).opacity(0.48 + 0.25 * energy), location: 0.76),
                            .init(color: .clear, location: 0.95)
                        ]),
                        startPoint: CGPoint(x: 0, y: eqY),
                        endPoint: CGPoint(x: w, y: eqY)
                    )
                )
            }
            .blur(radius: 9.0)
            .blendMode(.screen)

            // 3. Multi-Band Spectral Prism Dispersion (Red -> Orange -> Gold -> Cyan -> Azure)
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let eqY = h * 0.455
                let archHeight: CGFloat = 15.0 + CGFloat(energy) * 7.5
                let spread = 1.0 + energy * 0.85

                // Band 1: Crimson-Red & Fiery Orange upper arc
                let redOrangeBand = horizonRibbonPath(
                    width: w,
                    baseY: eqY - CGFloat(4.8 * spread),
                    archHeight: archHeight + 0.6,
                    thickness: CGFloat(6.2 + 5.5 * energy),
                    time: time,
                    energy: energy,
                    phaseOffset: 0.25
                )
                context.fill(
                    redOrangeBand,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0.06),
                            .init(color: Color(red: 0.85, green: 0.24, blue: 0.14).opacity(0.72 + 0.20 * energy), location: 0.24),
                            .init(color: Color(red: 1.00, green: 0.46, blue: 0.12).opacity(0.96), location: 0.50),
                            .init(color: Color(red: 0.90, green: 0.28, blue: 0.14).opacity(0.76 + 0.18 * energy), location: 0.76),
                            .init(color: .clear, location: 0.94)
                        ]),
                        startPoint: CGPoint(x: 0, y: eqY),
                        endPoint: CGPoint(x: w, y: eqY)
                    )
                )

                // Band 2: Electric Azure-Blue lower arc
                let azureBand = horizonRibbonPath(
                    width: w,
                    baseY: eqY + CGFloat(6.6 * spread),
                    archHeight: archHeight - 0.8,
                    thickness: CGFloat(8.5 + 7.5 * energy),
                    time: time,
                    energy: energy,
                    phaseOffset: -0.25
                )
                context.fill(
                    azureBand,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0.03),
                            .init(color: Color(red: 0.22, green: 0.48, blue: 0.94).opacity(0.68 + 0.22 * energy), location: 0.20),
                            .init(color: Color(red: 0.30, green: 0.68, blue: 1.00).opacity(0.96), location: 0.50),
                            .init(color: Color(red: 0.22, green: 0.48, blue: 0.94).opacity(0.68 + 0.22 * energy), location: 0.80),
                            .init(color: .clear, location: 0.97)
                        ]),
                        startPoint: CGPoint(x: 0, y: eqY),
                        endPoint: CGPoint(x: w, y: eqY)
                    )
                )

                // Band 3: Luminous Turquoise-Cyan mid-lower arc
                let cyanBand = horizonRibbonPath(
                    width: w,
                    baseY: eqY + CGFloat(3.0 * spread),
                    archHeight: archHeight - 0.3,
                    thickness: CGFloat(5.8 + 5.0 * energy),
                    time: time,
                    energy: energy,
                    phaseOffset: -0.10
                )
                context.fill(
                    cyanBand,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0.08),
                            .init(color: Color(red: 0.35, green: 0.84, blue: 0.98).opacity(0.75 + 0.18 * energy), location: 0.26),
                            .init(color: Color(red: 0.60, green: 0.96, blue: 1.00).opacity(0.98), location: 0.50),
                            .init(color: Color(red: 0.35, green: 0.84, blue: 0.98).opacity(0.75 + 0.18 * energy), location: 0.74),
                            .init(color: .clear, location: 0.92)
                        ]),
                        startPoint: CGPoint(x: 0, y: eqY),
                        endPoint: CGPoint(x: w, y: eqY)
                    )
                )

                // Band 4: Solar Golden-Yellow mid-upper arc
                let goldBand = horizonRibbonPath(
                    width: w,
                    baseY: eqY - CGFloat(1.8 * spread),
                    archHeight: archHeight + 0.2,
                    thickness: CGFloat(5.0 + 4.5 * energy),
                    time: time,
                    energy: energy,
                    phaseOffset: 0.10
                )
                context.fill(
                    goldBand,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0.10),
                            .init(color: Color(red: 0.98, green: 0.72, blue: 0.25).opacity(0.78 + 0.16 * energy), location: 0.28),
                            .init(color: Color(red: 1.00, green: 0.93, blue: 0.50).opacity(0.98), location: 0.50),
                            .init(color: Color(red: 0.98, green: 0.68, blue: 0.22).opacity(0.80 + 0.16 * energy), location: 0.72),
                            .init(color: .clear, location: 0.90)
                        ]),
                        startPoint: CGPoint(x: 0, y: eqY),
                        endPoint: CGPoint(x: w, y: eqY)
                    )
                )
            }
            .blur(radius: 2.6)
            .blendMode(.screen)

            // 4. Incandescent Warm-White Central Horizon Filament (pulses & ripples with voice)
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let eqY = h * 0.455
                let archHeight: CGFloat = 15.0 + CGFloat(energy) * 7.5

                let core = horizonRibbonPath(
                    width: w,
                    baseY: eqY + 0.4,
                    archHeight: archHeight,
                    thickness: CGFloat(3.4 + 4.2 * energy),
                    time: time,
                    energy: energy,
                    phaseOffset: 0.0
                )
                context.fill(
                    core,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0.12),
                            .init(color: Color(red: 1.0, green: 0.94, blue: 0.72).opacity(0.72 + 0.22 * energy), location: 0.28),
                            .init(color: Color(red: 1.0, green: 1.0, blue: 0.96).opacity(1.0), location: 0.50),
                            .init(color: Color(red: 1.0, green: 0.90, blue: 0.62).opacity(0.72 + 0.22 * energy), location: 0.72),
                            .init(color: .clear, location: 0.88)
                        ]),
                        startPoint: CGPoint(x: 0, y: eqY),
                        endPoint: CGPoint(x: w, y: eqY)
                    )
                )
            }
            .blur(radius: 1.2)
            .blendMode(.plusLighter)
        }
    }

    /// Computes the y-coordinate of the curved horizon (`⌒`) at normalized x `u` in `0...1`
    private func horizonY(
        u: Double,
        baseY: CGFloat,
        archHeight: CGFloat,
        time: Double,
        energy: Double,
        phaseOffset: Double
    ) -> CGFloat {
        let centered = (u - 0.5) * 2.0 // -1.0 ... 1.0
        let arch = max(0.0, 1.0 - centered * centered)
        let envelope = pow(arch, 1.35)

        // Dynamic multi-harmonic acoustic wave driven by real-time audio energy
        let speed = isSpeaking ? 5.8 : 1.2
        let t = time * speed + phaseOffset
        let harmonic1 = sin(u * 6.2 - t) * 0.55
        let harmonic2 = sin(u * 12.4 + t * 1.35) * 0.30
        let harmonic3 = cos(u * 18.0 - t * 1.70) * 0.15
        let waveAmplitude = 0.6 + energy * 8.5
        let wave = (harmonic1 + harmonic2 + harmonic3) * waveAmplitude * envelope

        return baseY - CGFloat(arch) * archHeight + CGFloat(wave)
    }

    /// Path covering the upper hemisphere (overshooting top/sides by 24pt so `.blur` only feathers the bottom curve)
    private func upperDomePath(
        width: CGFloat,
        baseY: CGFloat,
        archHeight: CGFloat,
        time: Double,
        energy: Double
    ) -> Path {
        let steps = 48
        var path = Path()
        path.move(to: CGPoint(x: -24, y: -24))
        path.addLine(to: CGPoint(x: width + 24, y: -24))
        path.addLine(to: CGPoint(x: width + 24, y: baseY))

        for i in (0...steps).reversed() {
            let u = Double(i) / Double(steps)
            let x = CGFloat(u) * width
            let y = horizonY(
                u: u,
                baseY: baseY,
                archHeight: archHeight,
                time: time,
                energy: energy,
                phaseOffset: 0.0
            )
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: -24, y: baseY))
        path.closeSubpath()
        return path
    }

    /// Builds a curved horizontal lens flare ribbon (`⌒`) with audio-reactive wave modulation
    private func horizonRibbonPath(
        width: CGFloat,
        baseY: CGFloat,
        archHeight: CGFloat,
        thickness: CGFloat,
        time: Double,
        energy: Double,
        phaseOffset: Double
    ) -> Path {
        let steps = 48
        var topPoints: [CGPoint] = []
        var bottomPoints: [CGPoint] = []

        for i in 0...steps {
            let u = Double(i) / Double(steps)
            let x = CGFloat(u) * width
            let centered = (u - 0.5) * 2.0
            let arch = max(0.0, 1.0 - centered * centered)
            let envelope = pow(arch, 1.4)

            let centerY = horizonY(
                u: u,
                baseY: baseY,
                archHeight: archHeight,
                time: time,
                energy: energy,
                phaseOffset: phaseOffset
            )

            // Audio-reactive thickness modulation along the beam
            let localPulse = 1.0 + 0.28 * energy * sin(u * 9.0 + time * 7.0 + phaseOffset)
            let halfThick = (thickness * 0.5) * CGFloat(envelope * localPulse)

            topPoints.append(CGPoint(x: x, y: centerY - halfThick))
            bottomPoints.append(CGPoint(x: x, y: centerY + halfThick))
        }

        var path = Path()
        if let first = topPoints.first {
            path.move(to: first)
            for pt in topPoints.dropFirst() {
                path.addLine(to: pt)
            }
            for pt in bottomPoints.reversed() {
                path.addLine(to: pt)
            }
            path.closeSubpath()
        }
        return path
    }
}
