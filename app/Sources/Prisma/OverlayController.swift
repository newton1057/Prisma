import AppKit
import SwiftUI
import Combine

final class OverlayPanel: NSPanel {
    var onClick: (() -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Allow the panel to sit flush with the physical top/bottom edges of the screen
    // (including over the menu bar / notch area) without AppKit clamping it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }
}

/// Forwards display-link ticks without retaining the overlay controller.
private final class DisplayLinkTarget: NSObject {
    private let tick: () -> Void

    init(_ tick: @escaping () -> Void) {
        self.tick = tick
    }

    @objc func step(_ link: CADisplayLink) {
        tick()
    }
}

final class OverlayController {
    let model = OverlayModel()

    private let settings: SettingsStore
    private var panel: OverlayPanel?
    private var hostingView: NSHostingView<OverlayView>?
    private var hideWorkItem: DispatchWorkItem?
    private var orderOutWorkItem: DispatchWorkItem?
    private var themeCancellable: AnyCancellable?
    private var hoverInfoCancellable: AnyCancellable?
    private var restCancellable: AnyCancellable?
    private var transitionID: Int = 0
    private var glideLink: CADisplayLink?
    var keepsVisible = false
    var onSelect: (() -> Void)?
    var agentSource: String? {
        didSet {
            if oldValue != agentSource { updateTheme() }
        }
    }
    var rowIndex = 0
    var rowCount = 1
    var rowSlotWidths: [CGFloat] = [OverlayController.activeSpacing]
    /// Screen shared by the whole row of session orbs, so one orb never
    /// jumps alone to the screen that happens to be active.
    var rowScreen: NSScreen?
    private var viewport: CGRect { OrbViewport.bounds(for: model.position) }
    /// Slot widths for waiting (compact) and active (thinking, speaking or hovered) orbs.
    static let inactiveSpacing: CGFloat = 78
    static let activeSpacing: CGFloat = 110

    deinit {
        glideLink?.invalidate()
    }

    init(settings: SettingsStore) {
        self.settings = settings
        self.model.position = settings.position
        self.model.haloTheme = settings.theme(for: agentSource)
        self.model.showHoverInfo = settings.showHoverInfo
        self.model.restsWhenIdle = settings.restIdleOrbs
        self.themeCancellable = Publishers.CombineLatest(
            Publishers.CombineLatest4(
                settings.$haloTheme,
                settings.$codexTheme,
                settings.$claudeTheme,
                settings.$openCodeTheme
            ),
            Publishers.CombineLatest(
                settings.$museTheme,
                settings.$antigravityTheme
            )
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateTheme()
        }
        self.hoverInfoCancellable = settings.$showHoverInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.model.showHoverInfo = enabled
            }
        self.restCancellable = settings.$restIdleOrbs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.model.restsWhenIdle = enabled
            }
    }

    private func updateTheme() {
        model.haloTheme = settings.theme(for: agentSource)
    }

    func show() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        orderOutWorkItem?.cancel()
        orderOutWorkItem = nil
        transitionID += 1

        let sourceScreen = panel?.screen
        setPlacement(settings.position)
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }
        // A visible orb keeps sliding if it is on its way to a new place.
        position(panel, from: sourceScreen, animated: true)

        let now = Date().timeIntervalSinceReferenceDate
        let current = model.visible ? model.currentPresentation(at: now) : 0.0

        model.transitionFrom = current
        model.transitionTo = 1.0
        model.transitionStartTime = now
        model.transitionDuration = max(0.18, 0.82 * (1.0 - current))
        model.visible = true
        model.presentationChanged()

        panel.alphaValue = 1
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide(after delay: TimeInterval = 1.0, force: Bool = false) {
        guard force || !keepsVisible else { return }
        hideWorkItem?.cancel()
        orderOutWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel else { return }
            self.transitionID += 1
            let currentID = self.transitionID

            let now = Date().timeIntervalSinceReferenceDate
            let current = self.model.visible ? self.model.currentPresentation(at: now) : 1.0
            let retractDuration: TimeInterval = max(0.18, 0.70 * current)

            self.model.transitionFrom = current
            self.model.transitionTo = 0.0
            self.model.transitionStartTime = now
            self.model.transitionDuration = retractDuration
            self.model.presentationChanged()

            let finishWork = DispatchWorkItem { [weak self] in
                guard let self, self.transitionID == currentID else { return }
                self.model.visible = false
                self.model.audioLevel = 0
                self.stopGlide()
                panel.orderOut(nil)
            }
            self.orderOutWorkItem = finishWork
            DispatchQueue.main.asyncAfter(deadline: .now() + retractDuration + 0.04, execute: finishWork)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func setSpeaking(_ speaking: Bool) {
        model.isSpeaking = speaking
        if !speaking {
            model.audioLevel = 0
        }
    }

    func setRenderingSuspended(_ suspended: Bool) {
        guard model.isRenderingSuspended != suspended else { return }
        if suspended { stopGlide() }
        model.setRenderingSuspended(suspended)
        if !suspended { reposition() }
    }

    func setAudioLevel(_ level: Double) {
        model.audioLevel = min(max(level, 0), 1)
    }

    func setProgress(_ progress: Double) {
        model.progress = min(max(progress, 0), 1)
    }

    func setCaption(_ text: String) {
        model.caption = "PRISMA"
    }

    /// Moves the orb to its place in the row. When `animated`, a visible orb
    /// slides there (optionally after `delay`) instead of jumping.
    func reposition(animated: Bool = false, delay: TimeInterval = 0) {
        let sourceScreen = panel?.screen
        setPlacement(settings.position)
        guard let panel else { return }
        position(panel, from: sourceScreen, animated: animated, delay: delay)
    }

    private func createPanel() {
        let panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: viewport.size))
        panel.onClick = { [weak self] in
            self?.onSelect?()
        }
        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.sizingOptions = []
        hosting.frame = hostingFrame
        let container = NSView(frame: NSRect(origin: .zero, size: viewport.size))
        container.clipsToBounds = true
        container.addSubview(hosting)
        panel.contentView = container
        hostingView = hosting
        self.panel = panel
    }

    private var hostingFrame: NSRect {
        NSRect(origin: NSPoint(x: -viewport.minX, y: -viewport.minY), size: OrbViewport.canvas)
    }

    private func setPlacement(_ placement: OverlayPosition) {
        guard model.position != placement else { return }
        let oldViewport = viewport
        let radius = 99 * CGFloat(model.currentScale(at: Date().timeIntervalSinceReferenceDate))
        let oldCenter = Self.orbCenter(for: model.position, radius: radius)
        model.position = placement
        guard let panel else { return }
        stopGlide()
        let origin = panel.frame.origin
        let newViewport = viewport
        let newCenter = Self.orbCenter(for: placement, radius: radius)
        // Start the next glide at the old screen position of the orb itself.
        panel.setFrame(NSRect(x: origin.x + oldCenter.x - newCenter.x - oldViewport.minX + newViewport.minX,
                              y: origin.y + oldCenter.y - newCenter.y - oldViewport.minY + newViewport.minY,
                              width: newViewport.width, height: newViewport.height), display: false)
        hostingView?.frame = hostingFrame
    }

    /// Enables mouse hit-testing only while the pointer is inside this orb's
    /// glass circle, so clicking the orb focuses its terminal without blocking
    /// clicks on the rest of the screen.
    func setInteractive(_ interactive: Bool) {
        guard let panel, panel.ignoresMouseEvents == interactive else { return }
        panel.ignoresMouseEvents = !interactive
    }

    private func position(_ panel: NSPanel, from sourceScreen: NSScreen?, animated: Bool, delay: TimeInterval = 0) {
        let connected = rowScreen.flatMap { row in NSScreen.screens.first { $0 == row } }
        guard let screen = connected ?? settings.resolvedScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let size = OrbViewport.canvas
        let origin: NSPoint

        switch model.position {
        case .top:
            // Top edge of panel is flush with the physical top border of the screen (frame.maxY)
            // so the orb emerges directly out of the top screen border and retracts back into it.
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height)
        case .left:
            // Left edge of panel is flush with the left border of the screen (frame.minX)
            origin = NSPoint(x: frame.minX, y: frame.midY - size.height / 2)
        case .right:
            // Right edge of panel is flush with the right border of the screen (frame.maxX)
            origin = NSPoint(x: frame.maxX - size.width, y: frame.midY - size.height / 2)
        case .bottom:
            // Bottom edge of panel is flush with the bottom border of the screen (frame.minY)
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY)
        case .center:
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        case .corner:
            origin = NSPoint(x: frame.maxX - size.width, y: frame.minY)
        }

        // The panels have transparent margins; position the visible circles,
        // not the edges of those larger panels, next to one another. Active
        // orbs claim a wider slot so their neighbours slide aside smoothly.
        let horizontal: CGFloat
        let vertical: CGFloat
        if model.position == .left || model.position == .right {
            let rowsPerColumn = max(1, Int((frame.height - 60) / Self.activeSpacing))
            let col = rowIndex / rowsPerColumn
            let first = col * rowsPerColumn
            let count = min(rowsPerColumn, rowCount - first)
            let item = rowIndex - first
            let heights = (first ..< first + count).map { index in
                index < rowSlotWidths.count ? rowSlotWidths[index] : Self.inactiveSpacing
            }
            let totalHeight = heights.reduce(0, +)
            let fromTop = heights.prefix(item).reduce(0, +) + (heights.indices.contains(item) ? heights[item] / 2 : 0)
            vertical = totalHeight / 2 - fromTop
            horizontal = CGFloat(col) * Self.activeSpacing * (model.position == .left ? 1 : -1)
        } else {
            let columns = max(1, Int((frame.width - 20) / Self.activeSpacing))
            let row = rowIndex / columns
            let first = row * columns
            let count = min(columns, rowCount - first)
            let column = rowIndex - first
            let widths = (first ..< first + count).map { index in
                index < rowSlotWidths.count ? rowSlotWidths[index] : Self.inactiveSpacing
            }
            let totalWidth = widths.reduce(0, +)
            let centerInRow = widths.prefix(column).reduce(0, +) + (widths.indices.contains(column) ? widths[column] / 2 : 0)
            let lastHalf = (widths.last ?? Self.inactiveSpacing) / 2
            horizontal = model.position == .corner
                ? centerInRow - (totalWidth - lastHalf)
                : centerInRow - totalWidth / 2
            vertical = CGFloat(row) * Self.activeSpacing * (model.position == .bottom || model.position == .corner ? 1 : -1)
        }
        let target = NSPoint(x: origin.x + horizontal + viewport.minX, y: origin.y + vertical + viewport.minY)

        let current = panel.frame.origin
        let distance = hypot(target.x - current.x, target.y - current.y)
        // Resizing around a screen edge can temporarily change panel.screen.
        let canSlide = animated && !model.isRenderingSuspended && panel.isVisible && model.visible && sourceScreen?.frame == frame
        guard canSlide, distance > 0.5 || glideLink != nil else {
            stopGlide()
            panel.setFrameOrigin(target)
            return
        }
        // Neighbours flow aside like drops of liquid; longer trips take a
        // little longer so their speed stays gentle.
        let duration = min(0.95, 0.52 + 0.14 * log2(1 + Double(distance / Self.activeSpacing)))
        model.glide(
            from: SIMD2(Double(current.x), Double(current.y)),
            to: SIMD2(Double(target.x), Double(target.y)),
            delay: delay,
            duration: duration
        )
        startGlide(panel)
    }

    /// Distance from `screenPoint` to this orb's centre when the pointer lies
    /// inside its glass circle, or `nil` when outside.
    func hoverDistance(to screenPoint: NSPoint) -> CGFloat? {
        guard let panel, panel.isVisible, model.visible else { return nil }
        let now = Date().timeIntervalSinceReferenceDate
        let current = model.currentScale(at: now)
        let effectiveScale = CGFloat(model.isHovered ? max(current, OverlayModel.activeScale) : current)
        let radius = 99.0 * effectiveScale
        let center = Self.orbCenter(for: model.position, radius: radius)
        let x = panel.frame.minX - viewport.minX + center.x
        let y = panel.frame.minY - viewport.minY + center.y
        let hitRadius = radius + (model.isHovered ? 8 : 4)
        let dist = hypot(screenPoint.x - x, screenPoint.y - y)
        return dist <= hitRadius ? dist : nil
    }

    private static func orbCenter(for placement: OverlayPosition, radius: CGFloat) -> NSPoint {
        switch placement {
        case .top: return NSPoint(x: 230, y: 305 - radius)
        case .left: return NSPoint(x: 20 + radius, y: 180)
        case .right: return NSPoint(x: 440 - radius, y: 180)
        case .bottom: return NSPoint(x: 230, y: 29 + radius)
        case .corner: return NSPoint(x: 371 - radius, y: 29 + radius)
        case .center: return NSPoint(x: 230, y: 279 - radius)
        }
    }

    /// Includes the destination while sliding, so a stationary pointer can
    /// enter an orb as the row moves without polling the entire screen.
    var hoverTrackingBounds: NSRect? {
        guard let panel, panel.isVisible, model.visible else { return nil }
        let end = model.glidePosition(at: Date().timeIntervalSinceReferenceDate + 10)
        guard model.isGliding(at: Date().timeIntervalSinceReferenceDate) else { return panel.frame }
        return panel.frame.union(NSRect(origin: NSPoint(x: end.x, y: end.y), size: viewport.size))
    }

    // MARK: Sliding

    private func startGlide(_ panel: NSPanel) {
        guard glideLink == nil, let view = panel.contentView else { return }
        let target = DisplayLinkTarget { [weak self] in self?.stepGlide() }
        let link = view.displayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        glideLink = link
    }

    private func stepGlide() {
        guard let panel else {
            stopGlide()
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        let origin = model.glidePosition(at: now)
        let current = panel.frame.origin
        if abs(current.x - origin.x) > 0.25 || abs(current.y - origin.y) > 0.25 {
            panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
        }
        if !model.isGliding(at: now) {
            panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
            stopGlide()
        }
    }

    private func stopGlide() {
        glideLink?.invalidate()
        glideLink = nil
        model.endGlide()
    }
}
