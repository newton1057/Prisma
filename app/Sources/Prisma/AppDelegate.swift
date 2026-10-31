import AppKit
import SwiftUI
import Combine

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

        appState.testVoice = { [weak self] in
            guard let self else { return }
            self.speech.speak(
                text: "Hola. Soy Prisma. Esta es la voz que usaré para avisarte cuando terminen tus agentes.",
                mode: .full
            )
        }
        appState.stopSpeaking = { [weak self] in self?.speech.stop() }
        appState.openSettings = { [weak self] in self?.showSettings() }
        appState.quit = { NSApp.terminate(nil) }

        appState.piperReady = FileManager.default.fileExists(atPath: settings.piperModelPath)
            && FileManager.default.isExecutableFile(atPath: settings.piperPythonPath)

        setupStatusItem()
        startServer()
        cleanupOldTempFiles()

        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
                self.speech.speak(
                    text: request.text,
                    mode: self.settings.mode,
                    cwd: request.cwd,
                    sessionID: request.session_id,
                    engineOverride: request.engine,
                    voiceOverride: request.voice
                )
            },
            onStop: { [weak self] in
                self?.speech.stop()
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
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Ajustes…", action: #selector(settingsAction), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Prisma", action: #selector(quitAction), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func testVoiceAction() {
        appState.testVoice()
    }

    @objc private func stopAction() {
        speech.stop()
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
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 660),
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
