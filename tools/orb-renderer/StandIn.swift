import AppKit
import SwiftUI

enum OverlayPosition { case top, left, right, bottom, center, corner }

/// ImageRenderer cannot draw NSVisualEffectView. The offline tools replace it
/// with this stand-in for the `.hudWindow` material.
struct HarnessBlur: View {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat
    var alpha: CGFloat = 0.45
    var body: some View { Color(white: 0.12).opacity(Double(alpha)) }
}
