// Test-copy entry point. prepare.py exposes AppDelegate's internals only in
// an isolated source snapshot; none of this instrumentation ships in Prisma.
import AppKit
import Darwin

// Read the user's selected palettes, but never persist test-copy settings.
func benchmarkSetDefault(_ value: Any?, forKey: String) {}
@MainActor var benchmarkMouse: NSPoint?
@MainActor func benchmarkPointer() -> NSPoint { benchmarkMouse ?? NSEvent.mouseLocation }

func processUsage() -> (cpu: Double, footprint: UInt64) {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return (cpu, status == KERN_SUCCESS ? info.phys_footprint : 0)
}

@MainActor
final class PerformanceRun {
    let delegate: AppDelegate
    var timer: Timer?
    var stage = -1
    var stageStart = 0.0
    var previousTime = 0.0
    var previousCPU = 0.0
    var previousFrames: [String: Int] = [:]
    var samples: [[String: Any]] = []
    let output: String
    var stages: [(String, Int, Bool, Double)] {
        var result: [(String, Int, Bool, Double)] = [
        ("idle", 0, false, 13),
        ("thinking-1", 1, false, 4),
        ("thinking-3", 3, false, 4),
        ("thinking-6", 6, false, 4),
        ("settle-6", 0, false, 0),
        ("speaking-1-synthetic", 1, true, 4),
        ("returned-idle", 0, false, 13)
        ]
        #if PRISMA_PERFORMANCE_SUSPENSION
        result += [("display-suspended-6", 6, false, 4), ("display-resumed-6", 6, false, 4)]
        #endif
        if let selected = ProcessInfo.processInfo.environment["PRISMA_BENCHMARK_STAGES"] {
            let names = Set(selected.split(separator: ",").map(String.init))
            result = result.filter { names.contains($0.0) }.map { stage in
                (stage.0, stage.1, stage.2, stage.0 == "settle-6" ? 0 : max(13, stage.3))
            }
        }
        return result
    }

    init(delegate: AppDelegate, output: String) {
        self.delegate = delegate
        self.output = output
    }

    func start() {
        #if PRISMA_PERFORMANCE_SUSPENSION
        if ProcessInfo.processInfo.environment["PRISMA_BENCHMARK_VALIDATE_ONLY"] == "1" {
            validateRuntime()
            NSApp.terminate(nil)
            return
        }
        #endif
        nextStage()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    #if PRISMA_PERFORMANCE_SUSPENSION
    func validateRuntime() {
        let count = delegate.sessionOverlays.count
        let oldID = "prisma-runtime-check-before"
        let newID = "prisma-runtime-check-after"
        let orb = delegate.ensureSession(oldID, source: "claude-code", pid: Int(getpid()))
        let bounds = orb.hoverTrackingBounds!
        benchmarkMouse = NSPoint(x: bounds.midX, y: bounds.minY + 29 + 99 * OverlayModel.inactiveScale)
        precondition(delegate.hoverRegion?.contains(benchmarkMouse!) == true)
        delegate.updateHoveredOrb()
        precondition(orb.model.isHovered && delegate.hoveredOrbID == oldID, "hover should expand the new orb")
        let transferred = delegate.ensureSession(newID, source: "claude-code", pid: Int(getpid()))
        precondition(transferred === orb && delegate.sessionOverlays[oldID] == nil)
        precondition(delegate.hoveredOrbID == newID && delegate.metadataGeneration[oldID] == nil)
        benchmarkMouse = NSPoint(x: -100_000, y: -100_000)
        delegate.updateHoveredOrb()
        precondition(!orb.model.isHovered && delegate.hoveredOrbID == nil)
        delegate.endSession(newID, immediately: true)
        precondition(delegate.sessionOverlays.count == count && delegate.metadataGeneration[newID] == nil)
        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        precondition(delegate.sessionMonitor == nil && delegate.hoverTimer == nil)
        precondition(delegate.sessionOverlays.values.allSatisfy { $0.model.isRenderingSuspended })
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        precondition(delegate.renderingSuspended, "screen wake must not override system sleep")
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(!delegate.renderingSuspended && delegate.sessionMonitor != nil)
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        precondition(delegate.renderingSuspended)
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        precondition(delegate.sessionOverlays.values.allSatisfy { !$0.model.isRenderingSuspended })
        delegate.screenLockChanged(true)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        precondition(delegate.renderingSuspended, "display wake must not override the screen lock")
        delegate.screenLockChanged(false)
        precondition(!delegate.renderingSuspended && delegate.sessionMonitor != nil)
        #if PRISMA_PERFORMANCE_VIEWPORT
        validateViewport()
        #endif
        benchmarkMouse = nil
        print("Runtime checks passed: hover, handover, cache invalidation, close, display/system/session/lock suspension and resume")
        fflush(stdout)
    }
    #endif

    #if PRISMA_PERFORMANCE_VIEWPORT
    func validateViewport() {
        let original = delegate.settings.position
        defer { delegate.settings.position = original }
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let orb = OverlayController(settings: delegate.settings)
        orb.show()
        let panel = NSApp.windows.first { $0 is OverlayPanel && !existingWindows.contains(ObjectIdentifier($0)) }
        guard let panel else { preconditionFailure("Missing the native test panel") }
        var previousPointer: NSPoint?
        for position in [OverlayPosition.top, .left, .right, .bottom, .center, .corner] {
            delegate.settings.position = position
            if let previousPointer {
                orb.reposition(animated: true)
                precondition((orb.hoverDistance(to: previousPointer) ?? .infinity) < 1,
                             "Placement change jumped before gliding to \(position)")
            }
            orb.reposition()
            guard let hosting = panel.contentView?.subviews.first, let screen = panel.screen else {
                preconditionFailure("Missing hosting view or screen for \(position)")
            }
            let bounds = OrbViewport.bounds(for: position)
            precondition(panel.frame.size == bounds.size && hosting.frame.size == OrbViewport.canvas,
                         "Unexpected frame sizes for \(position): panel \(panel.frame.size), hosting \(hosting.frame.size)")
            precondition(hosting.frame.origin == NSPoint(x: -bounds.minX, y: -bounds.minY),
                         "Unexpected hosting origin for \(position): \(hosting.frame.origin)")
            let frame = screen.frame
            let radius = 99 * OverlayModel.activeScale
            let pointer: NSPoint
            switch position {
            case .top: pointer = NSPoint(x: frame.midX, y: frame.maxY - 55 - radius)
            case .bottom: pointer = NSPoint(x: frame.midX, y: frame.minY + 29 + radius)
            case .left: pointer = NSPoint(x: frame.minX + 20 + radius, y: frame.midY)
            case .right: pointer = NSPoint(x: frame.maxX - 20 - radius, y: frame.midY)
            case .center: pointer = NSPoint(x: frame.midX, y: frame.midY + 99 - radius)
            case .corner: pointer = NSPoint(x: frame.maxX - 89 - radius, y: frame.minY + 29 + radius)
            }
            precondition((orb.hoverDistance(to: pointer) ?? .infinity) < 1, "Moved hit target for \(position)")
            previousPointer = pointer
        }
        print("Native panel size, drawing origin and hit tests passed for all six placements")
    }
    #endif

    func nextStage() {
        stage += 1
        if stage == stages.count {
            timer?.invalidate()
            let data = try! JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
            try! data.write(to: URL(fileURLWithPath: output))
            NSApp.terminate(nil)
            return
        }
        let (_, active, speaking, _) = stages[stage]
        #if PRISMA_PERFORMANCE_SUSPENSION
        delegate.displayAsleep = stages[stage].0 == "display-suspended-6"
        delegate.applyRenderingAvailability()
        #endif
        let ids = delegate.sessionOrder
        for (i, id) in ids.enumerated() {
            guard let model = delegate.sessionOverlays[id]?.model else { continue }
            model.isSpeaking = speaking && i < active
            model.isThinking = !speaking && i < active
            model.audioLevel = speaking && i < active ? 0.35 : 0
        }
        stageStart = ProcessInfo.processInfo.systemUptime
        previousTime = stageStart
        previousCPU = processUsage().cpu
        previousFrames = delegate.sessionOverlays.mapValues { $0.model.benchmarkFrames }
        print("Starting \(stages[stage].0), \(ids.count) session orbs")
        fflush(stdout)
    }

    func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        let usage = processUsage()
        let elapsed = now - stageStart
        let frames = delegate.sessionOverlays.mapValues { $0.model.benchmarkFrames }
        let frameRates = frames.mapValues { _ in 0.0 }.merging(
            Dictionary(uniqueKeysWithValues: frames.map { id, n in
                (id, Double(n - (previousFrames[id] ?? n)) / (now - previousTime))
            }), uniquingKeysWith: { _, new in new })
        if elapsed >= stages[stage].3 {
            samples.append([
                "stage": stages[stage].0, "elapsed": elapsed,
                "unix_time": Date().timeIntervalSince1970,
                "cpu_seconds": usage.cpu - previousCPU,
                "frame_updates": frames.reduce(0) { $0 + max(0, $1.value - (previousFrames[$1.key] ?? $1.value)) },
                "cpu_percent": (usage.cpu - previousCPU) / (now - previousTime) * 100,
                "footprint_bytes": usage.footprint,
                "orbs": delegate.sessionOrder.count,
                "resting": delegate.sessionOverlays.values.filter { $0.model.isResting }.count,
                "hover_timer": delegate.hoverTimer != nil,
                "frames_per_second": frameRates
            ])
        }
        previousCPU = usage.cpu
        previousTime = now
        previousFrames = frames
        if elapsed >= stages[stage].3 + 15 { nextStage() }
    }
}

signal(SIGPIPE, SIG_IGN)
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
var benchmark: PerformanceRun?
DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
    let output = ProcessInfo.processInfo.environment["PRISMA_BENCHMARK_OUTPUT"]!
    benchmark = PerformanceRun(delegate: delegate, output: output)
    benchmark?.start()
}
app.run()
