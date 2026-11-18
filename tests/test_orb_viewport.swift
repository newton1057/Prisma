import AppKit
import SwiftUI

// Run with the offline renderer's stand-in for the native backdrop material.
@main
struct TestOrbViewport {
    @MainActor
    static func main() {
        let canvas = OrbViewport.canvas
        let width = Int(canvas.width * 2)
        let height = Int(canvas.height * 2)
        let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
        var count = 0
        var failures = 0

        for position in [OverlayPosition.top, .left, .right, .bottom, .center, .corner] {
            var now = 8_000.0
            let model = OverlayModel()
            model.clock = { now }
            model.position = position
            model.hasIdleState = true
            model.agentTitle = "Claude Code"
            model.sessionTitle = "An especially long title for the session information badge"
            model.visible = true
            model.transitionTo = 1
            model.transitionStartTime = now
            model.transitionDuration = 1
            let view = OverlayView(model: model)
            let bounds = OrbViewport.bounds(for: position)
            var visibleBounds = CGRect.null

            // Start the clock at the transparent endpoint and sample the
            // visible frames after it. ImageRenderer can emit uncomposited
            // Canvas pixels at an opacity of exactly zero.
            for tick in 0...200 {
                now = 8_000 + Double(tick) / 40
                if tick == 42 { model.isHovered = true }
                if tick == 70 { model.isThinking = true }
                if tick == 90 { model.isHovered = false }
                if tick == 120 { model.isThinking = false; model.isSpeaking = true }
                if tick == 158 {
                    model.transitionFrom = 1
                    model.transitionTo = 0
                    model.transitionStartTime = now
                }
                model.audioLevel = 0.75
                let content = view.canvas(at: now)
                guard tick > 0, tick.isMultiple(of: 4) else { continue }
                let reference = render(content)
                let x = Int(bounds.minX * 2)
                let y = Int((canvas.height - bounds.maxY) * 2)
                let cropWidth = Int(bounds.width * 2)
                let cropHeight = Int(bounds.height * 2)
                let original = pixels(reference, width: width, height: height)
                var missingAlpha: UInt8 = 0
                for row in 0..<height {
                    for column in 0..<width {
                        let alpha = original[(row * width + column) * 4 + 3]
                        if alpha > 1 {
                            visibleBounds = visibleBounds.union(CGRect(x: column, y: row, width: 1, height: 1))
                        }
                        if !(x..<x + cropWidth).contains(column) || !(y..<y + cropHeight).contains(row) {
                            missingAlpha = max(missingAlpha, alpha)
                        }
                    }
                }
                guard missingAlpha <= 1 else {
                    fputs("\(position) frame \(tick): clipped alpha \(missingAlpha)\n", stderr)
                    failures += 1
                    continue
                }
                if [20, 64, 104, 148, 176].contains(tick), let output {
                    let cropped = reference.cropping(to: CGRect(x: x, y: y, width: cropWidth, height: cropHeight))!
                    let data = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])!
                    try! data.write(to: output.appendingPathComponent("\(position)-\(tick).png"))
                }
                count += 1
            }
            print("\(position) visible bounds at 2x: \(visibleBounds)")
        }
        guard failures == 0 else { exit(EXIT_FAILURE) }
        print("Verified \(count) viewport frames across all six placements")
    }

    @MainActor
    private static func render(_ view: some View) -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage!
    }

    private static func pixels(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        precondition(image.width == width && image.height == height)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }
}
