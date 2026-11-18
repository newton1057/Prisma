// Offline renderer for the Prisma orb. It draws SiriLiquidGlassOrbView frame
// by frame through a scripted sequence of state changes, so transitions can be
// inspected without the app. render.sh builds it together with the app's
// OverlayView.swift. See README.md.
import SwiftUI
import AppKit

/// Deterministic, speech-like level in 30 Hz steps with the same attack and
/// release smoothing as SpeechSession's meter.
struct SyntheticVoice {
    private var smoothed = 0.0
    private var lastStep = -1

    mutating func level(at t: Double) -> Double {
        let step = Int(t * 30)
        if step != lastStep {
            lastStep = step
            let ts = Double(step) / 30
            let syllable = max(0, sin(ts * 2 * .pi * 4.3)) * (0.55 + 0.45 * sin(ts * 1.7 + 1))
            let word = 0.5 + 0.5 * sin(ts * 2 * .pi * 0.9)
            let raw = min(1, max(0, syllable * (0.35 + 0.65 * word)))
            smoothed = raw > smoothed ? smoothed * 0.32 + raw * 0.68 : smoothed * 0.72 + raw * 0.28
        }
        return smoothed
    }
}

struct Event {
    let at: Double
    let apply: (OverlayModel) -> Void
}

@MainActor
func renderFrame(model: OverlayModel, now: Double, size: CGFloat) -> CGImage? {
    let content = ZStack {
        // Desktop-like backdrop behind the glass.
        LinearGradient(colors: [Color(red: 0.20, green: 0.24, blue: 0.32), Color(red: 0.36, green: 0.30, blue: 0.34)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        SiriLiquidGlassOrbView(frame: model.frame(at: now))
    }
    .frame(width: size, height: size)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    return renderer.cgImage
}

func writePNG(_ image: CGImage, to url: URL) {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

@main
struct Harness {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "frames")
        let fps = args.count > 2 ? Double(args[2]) ?? 30 : 30
        let scenario = args.count > 3 ? args[3] : "cycle"
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        var virtualNow = 800_000_000.0
        let base = virtualNow
        let model = OverlayModel()
        model.clock = { virtualNow }
        model.idlePhase = 2.37
        model.visible = true
        // Only `rest` lets the waiting light come to rest; the other scenarios
        // keep it moving so they show the same motion as before resting existed.
        model.restsWhenIdle = scenario == "rest"
        // Settle in the waiting state before the recording starts; `rest`
        // starts drifting just before it.
        virtualNow = base - (scenario == "rest" ? 1.5 : 10)
        model.hasIdleState = true
        virtualNow = base

        var events: [Event] = []
        var duration = 9.0
        switch scenario {
        case "cycle", "silent":
            // waiting → thinking at 1.0 s → voice at 3.6 s → waiting at 6.6 s
            events = [
                Event(at: 1.0) { $0.isThinking = true },
                Event(at: 3.6) { m in m.isThinking = false; m.isSpeaking = true },
                Event(at: 6.6) { $0.isSpeaking = false },
            ]
        case "interrupt":
            // Rapid changes: every transition starts before the previous one ends.
            events = [
                Event(at: 0.5) { $0.isThinking = true },
                Event(at: 1.0) { m in m.isThinking = false; m.isSpeaking = true },
                Event(at: 1.6) { $0.isSpeaking = false },
                Event(at: 2.0) { $0.isThinking = true },
            ]
            duration = 4.0
        case "rest":
            let settle = OverlayModel.restDelay + OverlayModel.settleDuration
            let hover = settle - 1.5 + 1.4
            let leave = hover + 1.5
            let think = leave + settle + 0.9
            events = [
                Event(at: hover) { $0.isHovered = true },
                Event(at: leave) { $0.isHovered = false },
                Event(at: think) { $0.isThinking = true },
            ]
            duration = think + 2.0
        default:
            print("unknown scenario \(scenario); use cycle, silent, interrupt or rest")
            return
        }

        var voice = SyntheticVoice()
        var fired = 0
        let frames = Int(duration * fps)
        var log = "frame,t,voice,thinking,idle,audio\n"
        for f in 0..<frames {
            let t = Double(f) / fps
            while fired < events.count && events[fired].at <= t {
                virtualNow = base + events[fired].at
                events[fired].apply(model)
                fired += 1
            }
            virtualNow = base + t
            let audio = (model.isSpeaking && scenario != "silent") ? voice.level(at: t) : 0
            model.audioLevel = audio
            guard let image = renderFrame(model: model, now: virtualNow, size: 240) else {
                print("render failed at frame \(f)")
                continue
            }
            writePNG(image, to: outDir.appendingPathComponent(String(format: "f%04d.png", f)))
            let pose = model.frame(at: virtualNow)
            log += String(format: "%d,%.4f,%.4f,%.4f,%.4f,%.3f\n", f, t, pose.voice, pose.thinking, pose.idle, audio)
        }
        try! log.write(to: outDir.appendingPathComponent("weights.csv"), atomically: true, encoding: .utf8)
        print("wrote \(frames) frames to \(outDir.path)")
    }
}
