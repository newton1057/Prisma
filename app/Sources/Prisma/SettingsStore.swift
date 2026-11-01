import Foundation
import AppKit
import Combine
import Carbon

enum VoiceEngine: String, CaseIterable, Identifiable {
    case edge
    case piper
    case apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edge: return "Edge Neural TTS (Azure / Copilot)"
        case .piper: return "Piper Local (es-MX claude)"
        case .apple: return "Apple Paulina (0 MB)"
        }
    }
}

enum EdgeVoiceOption: String, CaseIterable, Identifiable {
    case ava = "en-US-AvaMultilingualNeural"
    case andrew = "en-US-AndrewMultilingualNeural"
    case emma = "en-US-EmmaMultilingualNeural"
    case brian = "en-US-BrianMultilingualNeural"
    case dalia = "es-MX-DaliaNeural"
    case jorge = "es-MX-JorgeNeural"
    case salome = "es-CO-SalomeNeural"
    case ximena = "es-ES-XimenaNeural"
    case alvaro = "es-ES-AlvaroNeural"
    case elena = "es-AR-ElenaNeural"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ava: return "Ava Copilot Multilingüe (Femenina · ES+EN nativo)"
        case .andrew: return "Andrew Copilot Multilingüe (Masculina · ES+EN nativo)"
        case .emma: return "Emma Copilot Multilingüe (Femenina · Conversacional)"
        case .brian: return "Brian Copilot Multilingüe (Masculina · Conversacional)"
        case .dalia: return "Dalia (es-MX · Femenina)"
        case .jorge: return "Jorge (es-MX · Masculina)"
        case .salome: return "Salomé (es-CO · Femenina)"
        case .ximena: return "Ximena (es-ES · Femenina)"
        case .alvaro: return "Álvaro (es-ES · Masculina)"
        case .elena: return "Elena (es-AR · Femenina)"
        }
    }
}

enum ReadMode: String, CaseIterable, Identifiable {
    case full
    case short
    case notice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Mensaje completo"
        case .short: return "Resumen corto"
        case .notice: return "Solo aviso"
        }
    }
}

enum OverlayPosition: String, CaseIterable, Identifiable {
    case top
    case left
    case right
    case bottom
    case center
    case corner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "Arriba al centro (Fila)"
        case .left: return "Izquierda al centro (Columna)"
        case .right: return "Derecha al centro (Columna)"
        case .bottom: return "Abajo al centro (Fila)"
        case .center: return "Centro de pantalla"
        case .corner: return "Esquina inferior derecha"
        }
    }
}

enum PositionShortcut: String, CaseIterable, Identifiable {
    case ctrlOptionP
    case ctrlShiftP
    case optionCommandP
    case ctrlOptionO
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ctrlOptionP: return "⌃⌥P (Control + Opción + P)"
        case .ctrlShiftP: return "⌃⇧P (Control + Shift + P)"
        case .optionCommandP: return "⌥⌘P (Opción + Comando + P)"
        case .ctrlOptionO: return "⌃⌥O (Control + Opción + O)"
        case .disabled: return "Desactivado"
        }
    }

    var carbonKey: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .ctrlOptionP:
            return (UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey))
        case .ctrlShiftP:
            return (UInt32(kVK_ANSI_P), UInt32(controlKey | shiftKey))
        case .optionCommandP:
            return (UInt32(kVK_ANSI_P), UInt32(optionKey | cmdKey))
        case .ctrlOptionO:
            return (UInt32(kVK_ANSI_O), UInt32(controlKey | optionKey))
        case .disabled:
            return nil
        }
    }
}

enum ScreenShortcut: String, CaseIterable, Identifiable {
    case ctrlOptionM
    case ctrlShiftM
    case optionCommandM
    case ctrlOptionS
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ctrlOptionM: return "⌃⌥M (Control + Opción + M)"
        case .ctrlShiftM: return "⌃⇧M (Control + Shift + M)"
        case .optionCommandM: return "⌥⌘M (Opción + Comando + M)"
        case .ctrlOptionS: return "⌃⌥S (Control + Opción + S)"
        case .disabled: return "Desactivado"
        }
    }

    var carbonKey: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .ctrlOptionM:
            return (UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey))
        case .ctrlShiftM:
            return (UInt32(kVK_ANSI_M), UInt32(controlKey | shiftKey))
        case .optionCommandM:
            return (UInt32(kVK_ANSI_M), UInt32(optionKey | cmdKey))
        case .ctrlOptionS:
            return (UInt32(kVK_ANSI_S), UInt32(controlKey | optionKey))
        case .disabled:
            return nil
        }
    }
}

struct DisplayOption: Identifiable, Equatable {
    let id: String
    let title: String
}

final class SettingsStore: ObservableObject {
    @Published var voice: VoiceEngine {
        didSet { defaults.set(voice.rawValue, forKey: Keys.voice) }
    }

    @Published var edgeVoice: String {
        didSet { defaults.set(edgeVoice, forKey: Keys.edgeVoice) }
    }

    @Published var mode: ReadMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }

    @Published var speed: Double {
        didSet { defaults.set(speed, forKey: Keys.speed) }
    }

    @Published var position: OverlayPosition {
        didSet { defaults.set(position.rawValue, forKey: Keys.position) }
    }

    @Published var positionShortcut: PositionShortcut {
        didSet { defaults.set(positionShortcut.rawValue, forKey: Keys.positionShortcut) }
    }

    @Published var targetDisplay: String {
        didSet { defaults.set(targetDisplay, forKey: Keys.targetDisplay) }
    }

    @Published var screenShortcut: ScreenShortcut {
        didSet { defaults.set(screenShortcut.rawValue, forKey: Keys.screenShortcut) }
    }

    func cyclePosition() {
        let all = OverlayPosition.allCases
        guard let index = all.firstIndex(of: position) else {
            position = .top
            return
        }
        position = all[(index + 1) % all.count]
    }

    static func displayID(of screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    func displayOptions() -> [DisplayOption] {
        var options: [DisplayOption] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let id = Self.displayID(of: screen)
            let w = Int(screen.frame.width)
            let h = Int(screen.frame.height)
            let rawName = screen.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name: String
            if !rawName.isEmpty {
                name = rawName
            } else if CGDisplayIsBuiltin(id) != 0 {
                name = "Pantalla integrada"
            } else {
                name = "Monitor externo \(index + 1)"
            }
            options.append(DisplayOption(id: "screen:\(id)", title: "Pantalla \(index + 1): \(name) (\(w)×\(h))"))
        }
        options.append(DisplayOption(id: "active", title: "Automático: Pantalla activa"))
        options.append(DisplayOption(id: "pointer", title: "Automático: Pantalla del cursor"))
        if !options.contains(where: { $0.id == targetDisplay }) {
            options.insert(DisplayOption(id: targetDisplay, title: "Pantalla seleccionada"), at: 0)
        }
        return options
    }

    func resolvedScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        if targetDisplay.hasPrefix("screen:"),
           let raw = UInt32(targetDisplay.dropFirst("screen:".count)),
           let match = screens.first(where: { Self.displayID(of: $0) == raw }) {
            return match
        }
        if targetDisplay == "pointer" {
            let mouse = NSEvent.mouseLocation
            if let match = screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
                return match
            }
        }
        if targetDisplay == "active" {
            return NSScreen.main ?? screens.first
        }
        return screens.first ?? NSScreen.main
    }

    func cycleScreen() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let current = resolvedScreen() ?? screens[0]
        let currentID = Self.displayID(of: current)
        let index = screens.firstIndex(where: { Self.displayID(of: $0) == currentID }) ?? 0
        let next = screens[(index + 1) % screens.count]
        targetDisplay = "screen:\(Self.displayID(of: next))"
    }

    @Published var haloTheme: HaloTheme {
        didSet { defaults.set(haloTheme.rawValue, forKey: Keys.haloTheme) }
    }

    @Published var codexTheme: HaloTheme {
        didSet { defaults.set(codexTheme.rawValue, forKey: Keys.codexTheme) }
    }

    @Published var claudeTheme: HaloTheme {
        didSet { defaults.set(claudeTheme.rawValue, forKey: Keys.claudeTheme) }
    }

    @Published var openCodeTheme: HaloTheme {
        didSet { defaults.set(openCodeTheme.rawValue, forKey: Keys.openCodeTheme) }
    }

    func theme(for source: String?) -> HaloTheme {
        switch source {
        case "codex": return codexTheme
        case "claude-code": return claudeTheme
        case "opencode": return openCodeTheme
        default: return haloTheme
        }
    }

    @Published var showThinking: Bool {
        didSet { defaults.set(showThinking, forKey: Keys.showThinking) }
    }

    @Published var showHoverInfo: Bool {
        didSet { defaults.set(showHoverInfo, forKey: Keys.showHoverInfo) }
    }

    @Published var stayVisible: Bool {
        didSet { defaults.set(stayVisible, forKey: Keys.stayVisible) }
    }

    @Published var duckAudio: Bool {
        didSet { defaults.set(duckAudio, forKey: Keys.duckAudio) }
    }

    @Published var duckLevel: Double {
        didSet { defaults.set(duckLevel, forKey: Keys.duckLevel) }
    }

    @Published var piperModelPath: String {
        didSet { defaults.set(piperModelPath, forKey: Keys.piperModelPath) }
    }

    @Published var piperPythonPath: String {
        didSet { defaults.set(piperPythonPath, forKey: Keys.piperPythonPath) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let voice = "voice"
        static let edgeVoice = "edgeVoice"
        static let mode = "mode"
        static let speed = "speed"
        static let position = "position"
        static let positionShortcut = "positionShortcut"
        static let targetDisplay = "targetDisplay"
        static let screenShortcut = "screenShortcut"
        static let haloTheme = "haloTheme"
        static let codexTheme = "codexTheme"
        static let claudeTheme = "claudeTheme"
        static let openCodeTheme = "openCodeTheme"
        static let showThinking = "showThinking"
        static let showHoverInfo = "showHoverInfo"
        static let stayVisible = "stayVisible"
        static let duckAudio = "duckAudio"
        static let duckLevel = "duckLevel"
        static let piperModelPath = "piperModelPath"
        static let piperPythonPath = "piperPythonPath"
    }

    init() {
        voice = VoiceEngine(rawValue: defaults.string(forKey: Keys.voice) ?? "") ?? .edge
        edgeVoice = defaults.string(forKey: Keys.edgeVoice) ?? EdgeVoiceOption.ava.rawValue
        mode = ReadMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .full
        speed = defaults.object(forKey: Keys.speed) as? Double ?? 1.0
        position = OverlayPosition(rawValue: defaults.string(forKey: Keys.position) ?? "") ?? .top
        positionShortcut = PositionShortcut(rawValue: defaults.string(forKey: Keys.positionShortcut) ?? "") ?? .ctrlOptionP
        if let savedDisplay = defaults.string(forKey: Keys.targetDisplay), !savedDisplay.isEmpty {
            targetDisplay = savedDisplay
        } else if let first = NSScreen.screens.first {
            targetDisplay = "screen:\(Self.displayID(of: first))"
        } else {
            targetDisplay = "active"
        }
        screenShortcut = ScreenShortcut(rawValue: defaults.string(forKey: Keys.screenShortcut) ?? "") ?? .ctrlOptionM
        let fallbackTheme = HaloTheme(rawValue: defaults.string(forKey: Keys.haloTheme) ?? "") ?? .prisma
        haloTheme = fallbackTheme
        codexTheme = HaloTheme(rawValue: defaults.string(forKey: Keys.codexTheme) ?? "") ?? fallbackTheme
        claudeTheme = HaloTheme(rawValue: defaults.string(forKey: Keys.claudeTheme) ?? "") ?? .solar
        openCodeTheme = HaloTheme(rawValue: defaults.string(forKey: Keys.openCodeTheme) ?? "") ?? .aurora
        showThinking = defaults.object(forKey: Keys.showThinking) as? Bool ?? true
        showHoverInfo = defaults.object(forKey: Keys.showHoverInfo) as? Bool ?? true
        stayVisible = defaults.object(forKey: Keys.stayVisible) as? Bool ?? true
        duckAudio = defaults.object(forKey: Keys.duckAudio) as? Bool ?? true
        duckLevel = defaults.object(forKey: Keys.duckLevel) as? Double ?? 0.35
        piperModelPath = defaults.string(forKey: Keys.piperModelPath) ?? ""
        piperPythonPath = defaults.string(forKey: Keys.piperPythonPath) ?? ""
    }
}
