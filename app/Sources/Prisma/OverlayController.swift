import AppKit
import SwiftUI
import Combine

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Allow the panel to sit flush with the physical top/bottom edges of the screen
    // (including over the menu bar / notch area) without AppKit clamping it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
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

final class OverlayController {
    let model = OverlayModel()

    private let settings: SettingsStore
    private var panel: OverlayPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var orderOutWorkItem: DispatchWorkItem?
    private var positionCancellable: AnyCancellable?
    private var transitionID: Int = 0
    // Generous canvas around the 276x198 orb so shadows and glow never clip on any edge
    private let panelSize = NSSize(width: 460, height: 360)

    init(settings: SettingsStore) {
        self.settings = settings
        self.model.position = settings.position
        self.positionCancellable = settings.$position
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosition in
                guard let self else { return }
                self.model.position = newPosition
                self.reposition()
            }
    }

    func show() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        orderOutWorkItem?.cancel()
        orderOutWorkItem = nil
        transitionID += 1

        if panel == nil {
            createPanel()
        }

        guard let panel else { return }
        model.position = settings.position
        position(panel)

        let now = Date().timeIntervalSinceReferenceDate
        let current = model.visible ? model.currentPresentation(at: now) : 0.0

        model.transitionFrom = current
        model.transitionTo = 1.0
        model.transitionStartTime = now
        model.transitionDuration = 0.48
        model.visible = true

        panel.alphaValue = 1
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide(after delay: TimeInterval = 1.0) {
        hideWorkItem?.cancel()
        orderOutWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel else { return }
            self.transitionID += 1
            let currentID = self.transitionID

            let now = Date().timeIntervalSinceReferenceDate
            let current = self.model.visible ? self.model.currentPresentation(at: now) : 1.0
            let retractDuration: TimeInterval = 0.44

            self.model.transitionFrom = current
            self.model.transitionTo = 0.0
            self.model.transitionStartTime = now
            self.model.transitionDuration = retractDuration

            let finishWork = DispatchWorkItem { [weak self] in
                guard let self, self.transitionID == currentID else { return }
                self.model.visible = false
                self.model.audioLevel = 0
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

    func setAudioLevel(_ level: Double) {
        model.audioLevel = min(max(level, 0), 1)
    }

    func setProgress(_ progress: Double) {
        model.progress = min(max(progress, 0), 1)
    }

    func setCaption(_ text: String) {
        model.caption = "PRISMA"
    }

    func reposition() {
        guard let panel else { return }
        position(panel)
    }

    private func createPanel() {
        let panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: panelSize))
        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hosting
        self.panel = panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let size = panelSize
        let origin: NSPoint

        switch settings.position {
        case .top:
            // Top edge of panel is flush with the physical top border of the screen (frame.maxY)
            // so the orb emerges directly out of the top screen border and retracts back into it.
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height)
        case .bottom:
            // Bottom edge of panel is flush with the bottom border of the screen (frame.minY)
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY)
        case .center:
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        case .corner:
            origin = NSPoint(x: frame.maxX - size.width, y: frame.minY)
        }

        panel.setFrameOrigin(origin)
    }
}
