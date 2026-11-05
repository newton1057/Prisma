import AppKit
import SwiftUI
import Combine
import Darwin
import Carbon

final class AppState: ObservableObject {
    @Published var serverRunning = false
    @Published var serverStatus = "Iniciando…"
    @Published var piperReady = false

    var testVoice: () -> Void = {}
    var stopSpeaking: () -> Void = {}
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let settings = SettingsStore()
    private let appState = AppState()

    private var config: AppConfig!
    private var overlay: OverlayController!
    private var speech: SpeechController!
    private var server: HTTPServer?
    private var thinkingSession: String?
    private var thinkingTimeout: DispatchWorkItem?
    private var terminateSignalSource: DispatchSourceSignal?
    private var sessionOverlays: [String: OverlayController] = [:]
    private var sessionOrder: [String] = []
    private var speechQueue: [SpeakRequest] = []
    private var activeSpeechSession: String?
    private var isSpeaking = false
    private var closingSessions: Set<String> = []
    private var resumedSessions: Set<String> = []
    private var sessionMonitor: DispatchSourceTimer?
    /// Agents whose sessions get their own persistent orb in the row.
    private let sessionSources: Set<String> = ["codex", "claude-code", "opencode"]
    /// Agent process behind each Claude Code and OpenCode orb, so the orb
    /// follows its window to a new conversation and leaves when it closes.
    private var sessionProcesses: [String: Int32] = [:]
    private var codexProcesses: [String: Int32] = [:]
    private var lastClickTime: TimeInterval = 0
    /// Ends wait a moment in case the same window continues (/clear, /resume).
    private var pendingEnds: [String: DispatchWorkItem] = [:]
    /// Claude Code transcripts watched while thinking: it has no interrupt hook.
    private var thinkingTranscripts: [String: (path: String, offset: UInt64)] = [:]
    /// Open OpenCode windows (process → folder) and the orbs that belong to OpenCode.
    private var openCodeWindows: [Int32: String] = [:]
    private var openCodeOrbs: Set<String> = []
    private var orbFolders: [String: String] = [:]
    private var orbActivity: [String: Date] = [:]
    private var codexTitleCache: [String: String] = [:]
    private var codexIndexMTime: Date?
    private var claudeTitleCache: [String: String] = [:]
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hoverTimer: DispatchSourceTimer?
    private var hotKeyRef: EventHotKeyRef?
    private var screenHotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var shortcutCancellable: AnyCancellable?
    private var screenShortcutCancellable: AnyCancellable?
    private var displayCancellable: AnyCancellable?
    private static weak var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        config = AppConfig.loadOrCreate()

        if let python = config.piperPython,
           FileManager.default.isExecutableFile(atPath: python) {
            settings.piperPythonPath = python
        }
        if let model = config.piperModel,
           FileManager.default.fileExists(atPath: model) {
            settings.piperModelPath = model
        }

        overlay = OverlayController(settings: settings)
        speech = SpeechController(config: config, settings: settings, overlay: overlay)
        speech.onFinish = { [weak self] in
            let finished = self?.activeSpeechSession
            self?.isSpeaking = false
            self?.activeSpeechSession = nil
            if let finished { self?.finishClosingSessionIfReady(finished) }
            self?.playNextSpeech()
        }

        appState.testVoice = { [weak self] in
            guard let self else { return }
            self.speechQueue.append(SpeakRequest(text: "Hola. Soy Prisma. Esta es la voz que usaré para avisarte cuando terminen tus agentes."))
            self.playNextSpeech()
        }
        appState.stopSpeaking = { [weak self] in self?.stopAll() }
        appState.openSettings = { [weak self] in self?.showSettings() }
        appState.quit = { NSApp.terminate(nil) }

        appState.piperReady = FileManager.default.fileExists(atPath: settings.piperModelPath)
            && FileManager.default.isExecutableFile(atPath: settings.piperPythonPath)

        Self.shared = self
        setupStatusItem()
        startServer()
        startSessionMonitor()
        startHoverMonitor()
        installHotKeyHandler()
        registerPositionHotKey(settings.positionShortcut)
        registerScreenHotKey(settings.screenShortcut)
        shortcutCancellable = settings.$positionShortcut
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shortcut in
                self?.registerPositionHotKey(shortcut)
            }
        screenShortcutCancellable = settings.$screenShortcut
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shortcut in
                self?.registerScreenHotKey(shortcut)
            }
        displayCancellable = settings.$targetDisplay
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.overlay.rowScreen = self.settings.resolvedScreen()
                self.overlay.reposition()
                self.arrangeSessions()
            }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.overlay.rowScreen = self.settings.resolvedScreen()
            self.overlay.reposition()
            self.arrangeSessions()
        }
        installTerminationHandler()
        cleanupOldTempFiles()

        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionMonitor?.cancel()
        hoverTimer?.cancel()
        if let existing = hotKeyRef { UnregisterEventHotKey(existing) }
        if let existingScreen = screenHotKeyRef { UnregisterEventHotKey(existingScreen) }
        if let handler = hotKeyHandler { RemoveEventHandler(handler) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        speech?.shutdown()
        server?.stop()
        try? FileManager.default.removeItem(at: AppPaths.runtime)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func startServer() {
        let server = HTTPServer(
            port: config.port,
            token: config.token,
            onSpeak: { [weak self] request in
                guard let self else { return }
                if let id = request.session_id, !id.isEmpty, self.sessionSources.contains(request.source ?? "") {
                    _ = self.sessionOrb(id, source: request.source, pid: request.pid, folder: request.cwd)
                }
                self.stopWatchingTranscript(of: request.session_id)
                self.speechQueue.append(request)
                self.playNextSpeech()
            },
            onStop: { [weak self] in
                self?.stopAll()
            },
            onThinking: { [weak self] event in
                guard let self, self.settings.showThinking else { return }
                if let id = event.session_id, !id.isEmpty,
                   self.sessionSources.contains(event.source ?? "") || self.sessionOverlays[id] != nil {
                    let target = self.sessionOrb(id, source: event.source, pid: event.pid, folder: event.directory)
                    target.model.isThinking = true
                    target.show()
                    self.watchTranscript(event.transcript_path, of: id)
                    return
                }
                self.thinkingTimeout?.cancel()
                self.thinkingSession = event.session_id
                self.overlay.model.isThinking = true
                self.overlay.show()
                let timeout = DispatchWorkItem { [weak self] in
                    self?.thinkingSession = nil
                    self?.overlay.model.isThinking = false
                    self?.overlay.hide(after: 0)
                }
                self.thinkingTimeout = timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 3600, execute: timeout)
            },
            onInterrupt: { [weak self] event in
                guard let self else { return }
                if let id = event.session_id, let target = self.sessionOverlays[id] {
                    target.model.isThinking = false
                    self.stopWatchingTranscript(of: id)
                    return
                }
                guard self.overlay.model.isThinking, self.thinkingSession == event.session_id else { return }
                self.thinkingTimeout?.cancel()
                self.thinkingSession = nil
                self.overlay.model.isThinking = false
                self.overlay.hide(after: 0)
            },
            onSessionStart: { [weak self] event in
                guard let self, let id = event.session_id else { return }
                _ = self.sessionOrb(id, source: event.source, pid: event.pid, folder: event.directory)
            },
            onSessionEnd: { [weak self] id in
                guard let self, !self.resumedSessions.contains(id) else { return }
                self.endSession(id)
            }
        )

        server.onStateChange = { [weak self] running, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.appState.serverRunning = running
                self.appState.serverStatus = message
                if running {
                    if let actual = self.server?.boundPort, actual > 0 {
                        self.config.port = actual
                    }
                    self.config.writeRuntime()
                }
            }
        }

        self.server = server
        server.start()
    }

    private func startSessionMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "Prisma.CodexSessions"))
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in
            let processes = CodexSessionsMonitor.processList()
            let sessions = processes.map(CodexSessionsMonitor.resumedSessions(in:))
            let codexPIDs = processes.map(CodexSessionsMonitor.resumedSessionPIDs(in:)) ?? [:]
            let claude = processes.map(ClaudeCodeWindows.windows(in:))
            let openCode = processes.map(OpenCodeWindows.windows(in:))
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let sessions { self.updateResumedSessions(sessions, pids: codexPIDs) }
                self.checkSessionProcesses()
                if let claude { self.updateClaudeWindows(claude) }
                if let openCode { self.updateOpenCodeWindows(openCode) }
                self.checkThinkingTranscripts()
            }
        }
        sessionMonitor = timer
        timer.resume()
    }

    private func updateResumedSessions(_ sessions: [String], pids: [String: Int32] = [:]) {
        let current = Set(sessions)
        let closed = resumedSessions.subtracting(current)
        resumedSessions = current
        for (id, pid) in pids { codexProcesses[id] = pid }
        for id in sessions { _ = ensureSession(id, source: "codex", pid: pids[id].map(Int.init)) }
        for id in closed {
            codexProcesses[id] = nil
            endSession(id)
        }
    }

    /// The orb of an agent session, created or taken over as needed.
    private func sessionOrb(_ id: String, source: String?, pid: Int?, folder: String?) -> OverlayController {
        source == "opencode" ? openCodeOrb(id, folder: folder) : ensureSession(id, source: source, pid: pid)
    }

    /// OpenCode sessions take over the orb of the window that shows them; a
    /// window opened in the same folder is that window.
    private func openCodeOrb(_ id: String, folder: String?) -> OverlayController {
        defer {
            openCodeOrbs.insert(id)
            orbActivity[id] = Date()
            if let folder { orbFolders[id] = folder }
            if let target = sessionOverlays[id] {
                updateOrbMetadata(id, target: target)
            }
        }
        if sessionOverlays[id] != nil { return ensureSession(id, source: "opencode") }
        let candidates = openCodeOrbs.filter { key in
            guard key != id, canHandOver(key) else { return false }
            guard let folder else { return true }
            let place = sessionProcesses[key].flatMap { openCodeWindows[$0] } ?? orbFolders[key]
            return OpenCodeWindows.window(in: place, shows: folder)
        }
        // A window's waiting orb first, otherwise the one idle the longest.
        let previous = candidates.min { a, b in
            let aWaiting = a.hasPrefix("opencode:"), bWaiting = b.hasPrefix("opencode:")
            if aWaiting != bWaiting { return aWaiting }
            return (orbActivity[a] ?? .distantPast) < (orbActivity[b] ?? .distantPast)
        }
        if let previous, let target = handOver(previous, to: id) {
            target.agentSource = "opencode"
            closingSessions.remove(id)
            return target
        }
        return ensureSession(id, source: "opencode")
    }

    /// Every open Claude Code window waits with its own orb, even before its
    /// first hook; the hooks report the same process and take the orb over.
    private func updateClaudeWindows(_ windows: [Int32: String?]) {
        let owners = Set(sessionProcesses.values)
        for (pid, resumed) in windows.sorted(by: { $0.key < $1.key }) where !owners.contains(pid) {
            _ = ensureSession(resumed ?? "claude:\(pid)", source: "claude-code", pid: Int(pid))
        }
    }

    /// Every open OpenCode window waits with its own orb; sessions whose
    /// window was not noticed yet join it instead of adding another orb.
    private func updateOpenCodeWindows(_ windows: [Int32: String]) {
        openCodeWindows = windows
        let owners = Set(sessionProcesses.values)
        for (pid, folder) in windows.sorted(by: { $0.key < $1.key }) where !owners.contains(pid) {
            if let orphan = openCodeOrbs.sorted().first(where: {
                sessionProcesses[$0] == nil && OpenCodeWindows.window(in: folder, shows: orbFolders[$0])
            }) {
                sessionProcesses[orphan] = pid
                continue
            }
            let key = "opencode:\(pid)"
            _ = ensureSession(key, source: "opencode", pid: Int(pid))
            openCodeOrbs.insert(key)
            orbFolders[key] = folder
            orbActivity[key] = Date()
        }
        // A reply that finished after its window closed leaves once it is idle.
        for id in openCodeOrbs where sessionProcesses[id] == nil && canHandOver(id)
            && Date().timeIntervalSince(orbActivity[id] ?? .distantPast) > 20 {
            endSession(id, immediately: true)
        }
        // A one-shot `opencode run` can exit before its end event reaches the
        // plugin, leaving an orphan stuck thinking. Without a window process
        // and after a long silence it leaves whatever its state is; a speech
        // still playing or queued delays the close (finishClosingSessionIfReady),
        // and a live client that returns later gets a fresh orb from its next
        // event.
        for id in openCodeOrbs where sessionProcesses[id] == nil
            && Date().timeIntervalSince(orbActivity[id] ?? .distantPast) > 15 * 60 {
            sessionOverlays[id]?.model.isThinking = false
            endSession(id, immediately: true)
        }
    }

    @discardableResult
    private func ensureSession(_ id: String, source: String? = nil, pid: Int? = nil) -> OverlayController {
        closingSessions.remove(id)
        pendingEnds.removeValue(forKey: id)?.cancel()
        let resolvedSource = source ?? (openCodeOrbs.contains(id) || id.hasPrefix("opencode:")
            ? "opencode"
            : (id.hasPrefix("claude:") ? "claude-code" : "codex"))
        if resolvedSource == "codex", let pid, pid > 1 {
            codexProcesses[id] = Int32(clamping: pid)
        }
        let owner = ownerProcess(pid, source: resolvedSource)
        if let existing = sessionOverlays[id] {
            if let source, !source.isEmpty { existing.agentSource = source }
            if let owner { sessionProcesses[id] = owner }
            updateOrbMetadata(id, target: existing)
            return existing
        }
        // The same agent window moved on to another conversation (/clear,
        // /resume, another OpenCode session): its orb follows it in place.
        if let owner,
           let previous = sessionProcesses.first(where: { $0.value == owner && canHandOver($0.key) })?.key,
           let target = handOver(previous, to: id) {
            target.agentSource = resolvedSource
            updateOrbMetadata(id, target: target)
            return target
        }
        let target = OverlayController(settings: settings)
        target.agentSource = resolvedSource
        target.keepsVisible = true
        let phaseSeed = id.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        target.model.idlePhase = Double(phaseSeed % 628) / 100
        target.model.hasIdleState = true
        target.model.onActiveChange = { [weak self] in
            self?.arrangeSessions()
        }
        target.onSelect = { [weak self, weak target] in
            guard let self, let target else { return }
            if let key = self.sessionOverlays.first(where: { $0.value === target })?.key {
                self.focusSession(key)
            }
        }
        sessionOverlays[id] = target
        sessionOrder.append(id)
        if let owner { sessionProcesses[id] = owner }
        updateOrbMetadata(id, target: target)
        arrangeSessions()
        target.show()
        return target
    }

    /// Claude Code and OpenCode report their window's process; Codex keeps
    /// its own session lifecycle.
    private func ownerProcess(_ pid: Int?, source: String?) -> Int32? {
        guard let pid, pid > 1, source == "claude-code" || source == "opencode" else { return nil }
        return Int32(clamping: pid)
    }

    /// An orb can follow its window to a new conversation unless its own
    /// turn is still thinking or speaking.
    private func canHandOver(_ id: String) -> Bool {
        if pendingEnds[id] != nil { return true }
        guard let target = sessionOverlays[id], !closingSessions.contains(id) else { return false }
        return !target.model.isThinking && activeSpeechSession != id
            && !speechQueue.contains(where: { $0.session_id == id })
    }

    private func handOver(_ previous: String, to id: String) -> OverlayController? {
        guard let target = sessionOverlays.removeValue(forKey: previous) else { return nil }
        pendingEnds.removeValue(forKey: previous)?.cancel()
        closingSessions.remove(previous)
        sessionOverlays[id] = target
        if let index = sessionOrder.firstIndex(of: previous) { sessionOrder[index] = id }
        sessionProcesses[id] = sessionProcesses.removeValue(forKey: previous)
        thinkingTranscripts[previous] = nil
        if openCodeOrbs.remove(previous) != nil { openCodeOrbs.insert(id) }
        orbFolders[id] = orbFolders.removeValue(forKey: previous)
        orbActivity[id] = orbActivity.removeValue(forKey: previous)
        if activeSpeechSession == previous { activeSpeechSession = id }
        for index in speechQueue.indices where speechQueue[index].session_id == previous {
            speechQueue[index].session_id = id
        }
        return target
    }

    private static func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Orbs of Claude Code and OpenCode windows leave when the window closes,
    /// even if the agent could not send its session-end hook.
    private func checkSessionProcesses() {
        for (id, owner) in sessionProcesses where !Self.processIsAlive(owner) {
            endSession(id, immediately: true)
        }
    }

    private func watchTranscript(_ path: String?, of id: String) {
        guard let path, !path.isEmpty else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.uint64Value ?? 0
        thinkingTranscripts[id] = (path, size)
    }

    private func stopWatchingTranscript(of id: String?) {
        guard let id else { return }
        thinkingTranscripts[id] = nil
    }

    /// Claude Code has no hook for Escape, but it writes the interruption to
    /// its transcript; the orb then returns to waiting.
    private func checkThinkingTranscripts() {
        for (id, watched) in thinkingTranscripts {
            guard let target = sessionOverlays[id], target.model.isThinking else {
                thinkingTranscripts[id] = nil
                continue
            }
            guard let handle = FileHandle(forReadingAtPath: watched.path) else { continue }
            defer { try? handle.close() }
            guard let end = try? handle.seekToEnd(), end > watched.offset else { continue }
            let start = max(watched.offset, end > 65_536 ? end - 65_536 : 0)
            try? handle.seek(toOffset: start)
            let added = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
            thinkingTranscripts[id] = (watched.path, end)
            // The marker is the text of a user entry; quoted inside a reply or
            // a tool call it would appear escaped and does not count.
            if added.contains(#""text":"[Request interrupted by user"#) {
                target.model.isThinking = false
                thinkingTranscripts[id] = nil
            }
        }
    }

    /// Places every session orb in the row; visible orbs slide to their new
    /// place, after `delay` when they close the gap left by a leaving orb.
    private func arrangeSessions(delay: TimeInterval = 0) {
        // The row moves as a whole on the chosen display (or active/pointer display).
        let screen = settings.resolvedScreen() ?? NSScreen.main ?? NSScreen.screens.first
        let widths = sessionOrder.map { id -> CGFloat in
            guard let orb = sessionOverlays[id] else { return OverlayController.inactiveSpacing }
            return orb.model.isActive ? OverlayController.activeSpacing : OverlayController.inactiveSpacing
        }
        for (index, id) in sessionOrder.enumerated() {
            guard let target = sessionOverlays[id] else { continue }
            target.rowIndex = index
            target.rowCount = sessionOrder.count
            target.rowSlotWidths = widths
            target.rowScreen = screen
            target.reposition(animated: true, delay: delay)
        }
    }

    private func startHoverMonitor() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateHoveredOrb()
                if event.type == .leftMouseDown {
                    self.handleScreenClick()
                }
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.updateHoveredOrb()
            return event
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.08)
        timer.setEventHandler { [weak self] in
            self?.updateHoveredOrb()
        }
        hoverTimer = timer
        timer.resume()
    }

    /// Expands the single orb under the pointer without blocking mouse clicks
    /// on the menu bar or windows behind the overlay panels.
    private func updateHoveredOrb() {
        guard !sessionOverlays.isEmpty else { return }
        let mouse = NSEvent.mouseLocation
        var closestID: String?
        var closestDistance = CGFloat.greatestFiniteMagnitude
        for (id, target) in sessionOverlays {
            guard let distance = target.hoverDistance(to: mouse), distance < closestDistance else { continue }
            closestDistance = distance
            closestID = id
        }
        for (id, target) in sessionOverlays {
            let hovered = (id == closestID)
            if target.model.isHovered != hovered {
                if hovered {
                    updateOrbMetadata(id, target: target)
                }
                target.model.isHovered = hovered
            }
            target.setInteractive(hovered)
        }
    }

    private func updateOrbMetadata(_ id: String, target: OverlayController) {
        let source = target.agentSource ?? "codex"
        let agentName: String
        switch source {
        case "codex": agentName = "Codex"
        case "claude-code": agentName = "Claude Code"
        case "opencode": agentName = "OpenCode"
        default: agentName = "Prisma"
        }
        if target.model.agentTitle != agentName {
            target.model.agentTitle = agentName
        }

        let pid = sessionProcesses[id] ?? codexProcesses[id]
        let folder = pid.flatMap { openCodeWindows[$0] ?? OpenCodeWindows.workingDirectory(of: $0) } ?? orbFolders[id]
        let folderName = folder.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }

        let title: String
        switch source {
        case "codex":
            refreshCodexTitleCacheIfNeeded()
            if let threadName = codexTitleCache[id.lowercased()], !threadName.isEmpty {
                title = threadName
            } else if let folderName {
                title = folderName
            } else {
                title = String(id.prefix(8))
            }
        case "claude-code":
            if let claudeTitle = resolveClaudeTitle(for: id), !claudeTitle.isEmpty {
                title = claudeTitle
            } else if let folderName {
                title = folderName
            } else {
                title = id.hasPrefix("claude:") ? "Sesión activa" : String(id.prefix(8))
            }
        case "opencode":
            if let folderName {
                title = folderName
            } else {
                title = "Sesión activa"
            }
        default:
            title = folderName ?? ""
        }
        if target.model.sessionTitle != title {
            target.model.sessionTitle = title
        }
    }

    private func refreshCodexTitleCacheIfNeeded() {
        let indexURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: indexURL.path),
              let mtime = attrs[.modificationDate] as? Date else { return }
        if let last = codexIndexMTime, last == mtime, !codexTitleCache.isEmpty { return }
        codexIndexMTime = mtime
        guard let content = try? String(contentsOf: indexURL, encoding: .utf8) else { return }
        var map: [String: String] = [:]
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = (obj["id"] as? String)?.lowercased(),
                  let name = (obj["thread_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            map[id] = name
        }
        codexTitleCache = map
    }

    private func resolveClaudeTitle(for id: String) -> String? {
        guard !id.hasPrefix("claude:") else { return nil }
        if let cached = claudeTitleCache[id] { return cached }
        let projectsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for dir in dirs {
            let file = dir.appendingPathComponent("\(id).jsonl")
            guard FileManager.default.fileExists(atPath: file.path),
                  let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: 49_152)) ?? Data()
            let text = String(decoding: data, as: UTF8.self)
            var found: String?
            for line in text.split(separator: "\n") {
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
                if let custom = (obj["customTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
                    found = custom
                    break
                }
                if let summary = (obj["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                    found = summary
                    break
                }
                if found == nil,
                   (obj["type"] as? String) == "user",
                   let message = obj["message"] as? [String: Any],
                   let raw = message["content"] as? String {
                    let cleaned = Self.cleanPromptTitle(raw)
                    if !cleaned.isEmpty { found = cleaned }
                }
            }
            if let found {
                claudeTitleCache[id] = found
                return found
            }
        }
        return nil
    }

    private static func cleanPromptTitle(_ raw: String) -> String {
        if raw.contains("<local-command-") || raw.contains("<command-name>") { return "" }
        let stripped = raw.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let line = stripped
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        if line.count <= 42 { return line }
        return String(line.prefix(40)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func handleScreenClick() {
        let mouse = NSEvent.mouseLocation
        var closestID: String?
        var closestDistance = CGFloat.greatestFiniteMagnitude
        for (id, target) in sessionOverlays {
            guard let distance = target.hoverDistance(to: mouse), distance < closestDistance else { continue }
            closestDistance = distance
            closestID = id
        }
        if let closestID {
            focusSession(closestID)
        }
    }

    /// Brings the terminal window and tab of session `id` to the front when its
    /// orb is clicked.
    private func focusSession(_ id: String) {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastClickTime > 0.15 else { return }
        lastClickTime = now

        guard let pid = sessionProcesses[id] ?? codexProcesses[id] else {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first?
                .activate(options: [.activateAllWindows])
            return
        }
        let tty = Self.ttyPath(of: pid)
        let app = Self.terminalApp(for: pid)
        app?.activate(options: [.activateAllWindows])

        guard let tty else { return }
        let bundle = app?.bundleIdentifier ?? "com.apple.Terminal"
        DispatchQueue.global(qos: .userInitiated).async {
            let script: String
            if bundle == "com.googlecode.iterm2" {
                script = """
                on run argv
                    set targetTTY to item 1 of argv
                    tell application "iTerm2"
                        repeat with w in windows
                            repeat with t in tabs of w
                                repeat with s in sessions of t
                                    if tty of s is targetTTY then
                                        select t
                                        select s
                                        set index of w to 1
                                        activate
                                        return
                                    end if
                                end repeat
                            end repeat
                        end repeat
                        activate
                    end tell
                end run
                """
            } else if bundle == "com.apple.Terminal" {
                script = """
                on run argv
                    set targetTTY to item 1 of argv
                    tell application "Terminal"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if tty of t is targetTTY then
                                    set selected tab of w to t
                                    if miniaturized of w is true then set miniaturized of w to false
                                    set index of w to 1
                                    activate
                                    return
                                end if
                            end repeat
                        end repeat
                        activate
                    end tell
                end run
                """
            } else {
                return
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script, tty]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
        }
    }

    private static func ttyPath(of pid: Int32) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.e_tdev != 0, info.e_tdev != UInt32.max,
              let name = devname(Int32(bitPattern: info.e_tdev), mode_t(S_IFCHR)) else { return nil }
        return "/dev/" + String(cString: name)
    }

    private static func terminalApp(for pid: Int32) -> NSRunningApplication? {
        var current = pid
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        for _ in 0..<12 where current > 1 {
            if let app = NSRunningApplication(processIdentifier: current),
               app.activationPolicy == .regular {
                return app
            }
            var info = proc_bsdinfo()
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, size) == size else { break }
            let parent = Int32(bitPattern: info.pbi_ppid)
            if parent == current { break }
            current = parent
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first
    }

    private func endSession(_ id: String, immediately: Bool = false) {
        guard sessionOverlays[id] != nil else { return }
        if !immediately, let owner = sessionProcesses[id], Self.processIsAlive(owner) {
            // The window may go on in a new conversation and claim this orb.
            guard pendingEnds[id] == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingEnds[id] = nil
                self.closeSession(id)
            }
            pendingEnds[id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
            return
        }
        pendingEnds.removeValue(forKey: id)?.cancel()
        closeSession(id)
    }

    private func closeSession(_ id: String) {
        guard sessionOverlays[id] != nil else { return }
        closingSessions.insert(id)
        finishClosingSessionIfReady(id)
    }

    private func finishClosingSessionIfReady(_ id: String) {
        guard closingSessions.contains(id), activeSpeechSession != id,
              !speechQueue.contains(where: { $0.session_id == id }) else { return }
        closingSessions.remove(id)
        guard let target = sessionOverlays.removeValue(forKey: id) else { return }
        sessionOrder.removeAll { $0 == id }
        sessionProcesses[id] = nil
        thinkingTranscripts[id] = nil
        openCodeOrbs.remove(id)
        orbFolders[id] = nil
        orbActivity[id] = nil
        target.keepsVisible = false
        target.hide(after: 0, force: true)
        // Keep the controller alive until its liquid exit animation completes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { _ = target }
        // The neighbours start closing the gap once the bubble has begun to shrink.
        arrangeSessions(delay: 0.18)
        playNextSpeech()
    }

    private func playNextSpeech() {
        guard !isSpeaking, !speechQueue.isEmpty else { return }
        let request = speechQueue.removeFirst()
        let target = request.session_id.flatMap { sessionOverlays[$0] } ?? overlay!
        if target === overlay {
            thinkingTimeout?.cancel()
            thinkingSession = nil
        }
        speech.selectOverlay(target)
        activeSpeechSession = request.session_id
        isSpeaking = true
        let started = speech.speak(text: request.text, mode: settings.mode, cwd: request.cwd,
                                   sessionID: request.session_id, engineOverride: request.engine,
                                   voiceOverride: request.voice)
        target.model.isThinking = false
        if !started {
            isSpeaking = false
            activeSpeechSession = nil
            if let id = request.session_id { finishClosingSessionIfReady(id) }
            playNextSpeech()
        }
    }

    /// `pkill` / SIGTERM does not trigger `applicationWillTerminate`, so we
    /// handle it explicitly to make sure a ducked system volume is restored.
    private func installTerminationHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.speech?.shutdown()
            NSApp.terminate(nil)
        }
        source.resume()
        terminateSignalSource = source
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "waveform.circle.fill",
                accessibilityDescription: "Prisma"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Prisma"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Probar voz", action: #selector(testVoiceAction), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Detener", action: #selector(stopAction), keyEquivalent: "."))
        menu.addItem(NSMenuItem(title: "Cambiar posición de los orbes", action: #selector(cyclePositionAction), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Cambiar de pantalla", action: #selector(cycleScreenAction), keyEquivalent: "m"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Ajustes…", action: #selector(settingsAction), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Prisma", action: #selector(quitAction), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func installHotKeyHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let id = status == noErr ? hotKeyID.id : 1
            DispatchQueue.main.async {
                if id == 2 {
                    AppDelegate.shared?.settings.cycleScreen()
                } else {
                    AppDelegate.shared?.settings.cyclePosition()
                }
            }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &hotKeyHandler
        )
    }

    private func registerPositionHotKey(_ shortcut: PositionShortcut) {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        guard let (keyCode, modifiers) = shortcut.carbonKey else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5052534D), id: 1) // 'PRSM'
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func registerScreenHotKey(_ shortcut: ScreenShortcut) {
        if let existing = screenHotKeyRef {
            UnregisterEventHotKey(existing)
            screenHotKeyRef = nil
        }
        guard let (keyCode, modifiers) = shortcut.carbonKey else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5052534D), id: 2) // 'PRSM'
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &screenHotKeyRef
        )
    }

    @objc private func cyclePositionAction() {
        settings.cyclePosition()
    }

    @objc private func cycleScreenAction() {
        settings.cycleScreen()
    }

    @objc private func testVoiceAction() {
        appState.testVoice()
    }

    private func stopAll() {
        speechQueue.removeAll()
        isSpeaking = false
        activeSpeechSession = nil
        thinkingTimeout?.cancel()
        thinkingSession = nil
        overlay.model.isThinking = false
        for target in sessionOverlays.values { target.model.isThinking = false }
        thinkingTranscripts.removeAll()
        speech.stop()
        for id in Array(closingSessions) { finishClosingSessionIfReady(id) }
    }

    @objc private func stopAction() {
        stopAll()
    }

    @objc private func settingsAction() {
        showSettings()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 880),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Prisma"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(
                rootView: SettingsView(settings: settings, appState: appState)
            )
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func cleanupOldTempFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: AppPaths.temp,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate,
                  date < cutoff else { continue }
            try? fm.removeItem(at: file)
        }
    }
}
