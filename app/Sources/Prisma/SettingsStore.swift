import Foundation
import Combine

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
    case bottom
    case center
    case corner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "Arriba al centro"
        case .bottom: return "Abajo al centro"
        case .center: return "Centro de pantalla"
        case .corner: return "Esquina inferior derecha"
        }
    }
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
        stayVisible = defaults.object(forKey: Keys.stayVisible) as? Bool ?? true
        duckAudio = defaults.object(forKey: Keys.duckAudio) as? Bool ?? true
        duckLevel = defaults.object(forKey: Keys.duckLevel) as? Double ?? 0.35
        piperModelPath = defaults.string(forKey: Keys.piperModelPath) ?? ""
        piperPythonPath = defaults.string(forKey: Keys.piperPythonPath) ?? ""
    }
}
