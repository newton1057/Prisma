import Foundation
import AVFoundation
import AppKit

enum TextPreparer {
    static func prepare(text: String, mode: ReadMode, cwd: String?, isMultilingual: Bool = false) -> String {
        let cleaned = normalizeTechTerms(clean(text), isMultilingual: isMultilingual)
        switch mode {
        case .notice:
            return "Prisma terminó de trabajar."
        case .short:
            let short = firstSentences(cleaned, count: 2, maxChars: 320)
            return short.isEmpty ? "Prisma terminó de trabajar." : short
        case .full:
            if cleaned.count > 6000 {
                return String(cleaned.prefix(6000)) + " El mensaje era muy largo, así que lo he recortado."
            }
            return cleaned
        }
    }

    /// Prevents TTS tokenizers from splitting mixed-case words (iOS -> i-O-S, iPad -> i-Pad)
    /// or spelling out common tech terms awkwardly inside Spanish sentences.
    static func normalizeTechTerms(_ text: String, isMultilingual: Bool) -> String {
        var value = text
        let commonReplacements: [(String, String)] = [
            ("\\biOS\\b", "ái ou es"),
            ("\\bmacOS\\b", "mac ou es"),
            ("\\biPadOS\\b", "áipad ou es"),
            ("\\bwatchOS\\b", "guach ou es"),
            ("\\bvisionOS\\b", "víshon ou es"),
            ("\\biPad\\b", "áipad"),
            ("\\biPhone\\b", "áifon"),
            ("\\biCloud\\b", "áiclaud"),
            ("\\bMacBook\\b", "Mácbuk"),
            ("\\bAirPods\\b", "Érpods"),
            ("\\bCodexVoz\\b", "Códex Voz"),
            ("\\bOpenCode\\b", "Ópen Coud"),
            ("\\bOpenAI\\b", "Ópen Ei Ái"),
            ("\\bChatGPT\\b", "Chat Yi Pi Ti"),
            ("\\bGPT\\b", "Yi Pi Ti"),
            ("\\bTTS\\b", "Ti Ti Es"),
            ("\\bSiri\\s+AI\\b", "Siri Ei Ái"),
            ("\\bAI\\b", "Ei Ái"),
            ("\\bEdge\\s+Neural\\b", "Edch Neural"),
            ("\\bEdge\\b", "Edch"),
            ("\\bNotch\\b", "Noch"),
            ("\\bSwiftUI\\b", "Suift Yu Ái"),
            ("\\bAppKit\\b", "Ap Kit"),
            ("\\bGitHub\\b", "Guit Jab"),
            ("\\bYouTube\\b", "Yutub"),
            ("\\bWi-Fi\\b", "Guái Fái")
        ]
        for (pattern, replacement) in commonReplacements {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return value
    }

    static func clean(_ text: String) -> String {
        var value = text
        let patterns: [(String, String)] = [
            ("```[\\s\\S]*?```", " "),
            ("~~~[\\s\\S]*?~~~", " "),
            ("`[^`]*`", " "),
            ("!\\[[^\\]]*\\]\\([^)]*\\)", " "),
            ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1"),
            ("https?://\\S+", " "),
            ("(?m)^\\s{0,3}#{1,6}\\s*", ""),
            ("(?m)^\\s*[-*+]\\s+", ""),
            ("(?m)^\\s*\\d+\\.\\s+", ""),
            ("[*_~>#|]", " "),
            ("\\s+", " ")
        ]
        for (pattern, replacement) in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstSentences(_ text: String, count: Int, maxChars: Int) -> String {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { substring, _, _, stop in
            if let substring {
                let sentence = substring.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
            }
            if sentences.count >= count { stop = true }
        }
        var result = sentences.joined(separator: " ")
        if result.count > maxChars {
            result = String(result.prefix(maxChars)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return result
    }

    static func chunks(_ text: String, maxChars: Int = 260) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { substring, _, _, _ in
            if let substring {
                let sentence = substring.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
            }
        }
        if sentences.isEmpty { sentences = [text] }

        var result: [String] = []
        var current = ""

        for sentence in sentences {
            if sentence.count > maxChars {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                var wordChunk = ""
                for word in sentence.split(separator: " ") {
                    if wordChunk.count + word.count + 1 > maxChars, !wordChunk.isEmpty {
                        result.append(wordChunk)
                        wordChunk = ""
                    }
                    wordChunk += (wordChunk.isEmpty ? "" : " ") + word
                }
                if !wordChunk.isEmpty { result.append(wordChunk) }
            } else if current.count + sentence.count + 1 > maxChars, current.count >= 90 {
                result.append(current)
                current = sentence
            } else {
                current += (current.isEmpty ? "" : " ") + sentence
            }
        }

        if !current.isEmpty {
            if current.count < 80, let last = result.popLast() {
                result.append(last + " " + current)
            } else {
                result.append(current)
            }
        }
        return result
    }
}

final class SpeechController {
    private let config: AppConfig
    private let settings: SettingsStore
    private let overlay: OverlayController

    private var session: SpeechSession?
    private var appleSynth: AVSpeechSynthesizer?
    private var appleDelegate: AppleSpeechDelegate?
    private var appleMeterTimer: Timer?
    private var lastSignature: String?
    private var lastSignatureTime: Date?

    init(config: AppConfig, settings: SettingsStore, overlay: OverlayController) {
        self.config = config
        self.settings = settings
        self.overlay = overlay
    }

    private var piperPython: String? {
        let value = settings.piperPythonPath
        return value.isEmpty ? config.piperPython : value
    }

    private var piperModel: String? {
        let value = settings.piperModelPath
        return value.isEmpty ? config.piperModel : value
    }

    func speak(
        text: String,
        mode: ReadMode? = nil,
        cwd: String? = nil,
        sessionID: String? = nil,
        engineOverride: String? = nil,
        voiceOverride: String? = nil
    ) {
        let signature = "\(sessionID ?? "")|\(engineOverride ?? "")|\(voiceOverride ?? "")|\(text)"
        if signature == lastSignature,
           let lastSignatureTime,
           Date().timeIntervalSince(lastSignatureTime) < 2.0 {
            return
        }
        lastSignature = signature
        lastSignatureTime = Date()

        stop()

        let (resolvedEngine, resolvedEdgeVoice) = resolveEngineAndVoice(
            engineOverride: engineOverride,
            voiceOverride: voiceOverride
        )
        let isMultilingual = resolvedEdgeVoice.lowercased().contains("multilingual")

        let selectedMode = mode ?? settings.mode
        let prepared = TextPreparer.prepare(
            text: text,
            mode: selectedMode,
            cwd: cwd,
            isMultilingual: isMultilingual
        )
        guard !prepared.isEmpty else { return }

        overlay.setCaption("PRISMA")
        overlay.setProgress(0)
        overlay.setSpeaking(true)
        overlay.show()

        switch resolvedEngine {
        case .edge:
            if let python = piperPython {
                startSession(
                    text: prepared,
                    backend: .edge(python: python, voice: resolvedEdgeVoice),
                    fallbackToPiper: true
                )
            } else {
                speakWithPiperOrApple(prepared)
            }

        case .piper:
            speakWithPiperOrApple(prepared)

        case .apple:
            speakWithApple(prepared)
        }
    }

    private func resolveEngineAndVoice(
        engineOverride: String?,
        voiceOverride: String?
    ) -> (VoiceEngine, String) {
        var engine = settings.voice
        var edgeVoice = settings.edgeVoice

        if let rawEngine = engineOverride?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !rawEngine.isEmpty {
            if let parsed = VoiceEngine(rawValue: rawEngine) {
                engine = parsed
            } else if let mappedVoice = mapEdgeVoiceAlias(rawEngine) {
                engine = .edge
                edgeVoice = mappedVoice
            }
        }

        if let rawVoice = voiceOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawVoice.isEmpty {
            let lower = rawVoice.lowercased()
            if let parsedEngine = VoiceEngine(rawValue: lower) {
                engine = parsedEngine
            } else if let mappedVoice = mapEdgeVoiceAlias(rawVoice) {
                engine = .edge
                edgeVoice = mappedVoice
            }
        }

        return (engine, edgeVoice)
    }

    private func mapEdgeVoiceAlias(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "ava", "en-us-avamultilingualneural", "copilot", "copilot-f":
            return "en-US-AvaMultilingualNeural"
        case "andrew", "en-us-andrewmultilingualneural", "copilot-m":
            return "en-US-AndrewMultilingualNeural"
        case "emma", "en-us-emmamultilingualneural":
            return "en-US-EmmaMultilingualNeural"
        case "brian", "en-us-brianmultilingualneural":
            return "en-US-BrianMultilingualNeural"
        case "dalia", "es-mx-dalianeural", "es_mx_dalia", "mx-f":
            return "es-MX-DaliaNeural"
        case "jorge", "es-mx-jorgeneural", "es_mx_jorge", "mx-m":
            return "es-MX-JorgeNeural"
        case "salome", "salomé", "es-co-salomeneural", "co":
            return "es-CO-SalomeNeural"
        case "ximena", "es-es-ximenaneural", "es-f":
            return "es-ES-XimenaNeural"
        case "alvaro", "álvaro", "es-es-alvaroneural", "es-m":
            return "es-ES-AlvaroNeural"
        case "elena", "es-ar-elenaneural", "ar":
            return "es-AR-ElenaNeural"
        default:
            if trimmed.lowercased().hasSuffix("neural") {
                return trimmed
            }
            return nil
        }
    }

    private func speakWithPiperOrApple(_ prepared: String) {
        if let python = piperPython, let model = piperModel,
           FileManager.default.fileExists(atPath: model) {
            startSession(
                text: prepared,
                backend: .piper(python: python, model: model),
                fallbackToPiper: false
            )
        } else {
            speakWithApple(prepared)
        }
    }

    private func startSession(
        text: String,
        backend: SpeechSession.Backend,
        fallbackToPiper: Bool
    ) {
        let session = SpeechSession(
            text: text,
            backend: backend,
            speed: settings.speed,
            overlay: overlay,
            onFinish: { [weak self] in self?.finish() },
            onError: { [weak self] (started: Bool) in
                guard let self else { return }
                if started {
                    self.finish()
                } else if fallbackToPiper {
                    self.speakWithPiperOrApple(text)
                } else {
                    self.speakWithApple(text)
                }
            }
        )
        self.session = session
        session.start()
    }

    func stop() {
        session?.cancel()
        session = nil
        appleMeterTimer?.invalidate()
        appleMeterTimer = nil
        appleSynth?.stopSpeaking(at: .immediate)
        appleSynth = nil
        appleDelegate = nil
        overlay.setAudioLevel(0)
        overlay.setSpeaking(false)
        overlay.hide(after: 0.15)
    }

    private func finish() {
        session = nil
        appleMeterTimer?.invalidate()
        appleMeterTimer = nil
        overlay.setProgress(1)
        overlay.setAudioLevel(0)
        overlay.setSpeaking(false)
        overlay.hide(after: settings.stayVisible ? 1.2 : 0.2)
    }

    private func speakWithApple(_ text: String) {
        let synth = AVSpeechSynthesizer()
        let delegate = AppleSpeechDelegate(
            onFinish: { [weak self] in self?.finish() }
        )
        synth.delegate = delegate
        appleSynth = synth
        appleDelegate = delegate

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.es-MX.Paulina")
            ?? AVSpeechSynthesisVoice(language: "es-MX")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(settings.speed)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        synth.speak(utterance)

        appleMeterTimer?.invalidate()
        appleMeterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = Date().timeIntervalSinceReferenceDate
            let syllabic = max(0, sin(t * 9.5) * 0.55 + sin(t * 16.3 + 0.8) * 0.35 + 0.25)
            self.overlay.setAudioLevel(min(1.0, syllabic))
        }
    }
}

final class AppleSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
}

final class SpeechSession: NSObject {
    enum Backend {
        case edge(python: String, voice: String)
        case piper(python: String, model: String)
    }

    let id = UUID()

    private let chunks: [String]
    private let backend: Backend
    private let speed: Double
    private weak var overlay: OverlayController?
    private let onFinish: () -> Void
    private let onError: (Bool) -> Void

    private let synthesisQueue = DispatchQueue(label: "Prisma.Synthesis", qos: .userInitiated)
    private var audioURLs: [Int: URL] = [:]
    private var synthesizing: Set<Int> = []
    private var currentIndex = 0
    private var isPlaying = false
    private var didStartPlayback = false
    private var isCancelled = false
    private var didFinish = false
    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private var smoothedLevel: Double = 0

    init(
        text: String,
        backend: Backend,
        speed: Double,
        overlay: OverlayController,
        onFinish: @escaping () -> Void,
        onError: @escaping (Bool) -> Void
    ) {
        self.chunks = TextPreparer.chunks(text)
        self.backend = backend
        self.speed = speed
        self.overlay = overlay
        self.onFinish = onFinish
        self.onError = onError
        super.init()
    }

    func start() {
        guard !chunks.isEmpty else {
            onFinish()
            return
        }
        synthesize(0)
        if chunks.count > 1 {
            synthesize(1)
        }
    }

    func cancel() {
        isCancelled = true
        stopMetering()
        player?.stop()
        player = nil
        cleanupFiles()
    }

    private func synthesize(_ index: Int) {
        guard !isCancelled, index >= 0, index < chunks.count else { return }
        guard audioURLs[index] == nil, !synthesizing.contains(index) else { return }
        synthesizing.insert(index)

        let text = chunks[index]
        let indexCopy = index
        synthesisQueue.async { [weak self] in
            guard let self else { return }
            do {
                let url = try self.synthesizeChunk(text: text, index: indexCopy)
                DispatchQueue.main.async {
                    self.synthesizing.remove(indexCopy)
                    guard !self.isCancelled else { return }
                    self.audioURLs[indexCopy] = url
                    if indexCopy == 0 || (self.currentIndex == indexCopy && !self.isPlaying) {
                        self.play(indexCopy)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.synthesizing.remove(indexCopy)
                    guard !self.isCancelled else { return }
                    if !self.didStartPlayback && indexCopy == 0 {
                        self.onError(false)
                    } else if self.currentIndex == indexCopy && !self.isPlaying {
                        let next = indexCopy + 1
                        if next < self.chunks.count {
                            self.currentIndex = next
                            if self.audioURLs[next] != nil {
                                self.play(next)
                            } else {
                                self.synthesize(next)
                            }
                        } else {
                            self.finishIfNeeded()
                        }
                    }
                }
            }
        }
    }

    private func play(_ index: Int) {
        guard !isCancelled, let url = audioURLs[index] else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.isMeteringEnabled = true
            player.prepareToPlay()
            player.play()
            self.player = player
            self.isPlaying = true
            self.currentIndex = index
            self.didStartPlayback = true
            startMetering()

            let progress = Double(index) / Double(max(1, chunks.count))
            overlay?.setProgress(progress)
            overlay?.setCaption("PRISMA")

            if index + 1 < chunks.count, audioURLs[index + 1] == nil {
                synthesize(index + 1)
            }
            if index + 2 < chunks.count, audioURLs[index + 2] == nil {
                synthesize(index + 2)
            }
        } catch {
            onError(didStartPlayback)
        }
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, !self.isCancelled, let player = self.player, player.isPlaying else { return }
            player.updateMeters()
            let avg = Double(player.averagePower(forChannel: 0))
            let peak = Double(player.peakPower(forChannel: 0))
            let combinedDb = avg * 0.65 + peak * 0.35
            let normalized = max(0.0, min(1.0, (combinedDb + 44.0) / 40.0))
            let target = pow(normalized, 1.25)
            if target > self.smoothedLevel {
                self.smoothedLevel = self.smoothedLevel * 0.32 + target * 0.68
            } else {
                self.smoothedLevel = self.smoothedLevel * 0.72 + target * 0.28
            }
            self.overlay?.setAudioLevel(self.smoothedLevel)
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        smoothedLevel = 0
        overlay?.setAudioLevel(0)
    }

    private func finishIfNeeded() {
        guard !didFinish else { return }
        didFinish = true
        stopMetering()
        cleanupFiles()
        onFinish()
    }

    private func cleanupFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: AppPaths.temp, includingPropertiesForKeys: nil) else { return }
        let prefix = id.uuidString
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? fm.removeItem(at: file)
        }
    }

    private func synthesizeChunk(text: String, index: Int) throws -> URL {
        switch backend {
        case .edge(let python, let voice):
            return try runEdgeTTS(text: text, index: index, python: python, voice: voice)
        case .piper(let python, let model):
            return try runPiper(text: text, index: index, python: python, model: model)
        }
    }

    private func runEdgeTTS(text: String, index: Int, python: String, voice: String) throws -> URL {
        let output = AppPaths.temp.appendingPathComponent("\(id.uuidString)-\(index).mp3")
        let pct = Int(((speed - 1.0) * 100.0).rounded())
        let rateStr = pct >= 0 ? "+\(pct)%" : "\(pct)%"

        var lastError: Error?
        for _ in 0..<2 {
            guard !isCancelled else { break }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [
                "-m", "edge_tts",
                "--voice", voice,
                "--rate=\(rateStr)",
                "--text", text,
                "--write-media", output.path
            ]

            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0,
                   let attrs = try? FileManager.default.attributesOfItem(atPath: output.path),
                   let size = attrs[.size] as? NSNumber,
                   size.intValue > 0 {
                    return output
                }
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8) ?? "edge-tts no pudo sintetizar."
                lastError = NSError(
                    domain: "Prisma.EdgeTTS",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(
            domain: "Prisma.EdgeTTS",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "edge-tts falló"]
        )
    }

    private func runPiper(text: String, index: Int, python: String, model: String) throws -> URL {
        let output = AppPaths.temp.appendingPathComponent("\(id.uuidString)-\(index).wav")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [
            "-m", "piper",
            "-m", model,
            "-f", output.path,
            "--length-scale", String(1.0 / max(0.5, speed))
        ]

        let stdinPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        try process.run()
        if let data = text.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        try? stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "Piper no pudo sintetizar."
            throw NSError(
                domain: "Prisma.Piper",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        return output
    }
}

extension SpeechSession: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            guard !self.isCancelled else { return }
            self.isPlaying = false
            self.player = nil
            let next = self.currentIndex + 1

            if next < self.chunks.count {
                // Advance currentIndex BEFORE checking audioURLs[next] so if `next` is still
                // synthesizing, its completion handler sees `self.currentIndex == indexCopy` and plays it!
                self.currentIndex = next
                if self.audioURLs[next] != nil {
                    self.play(next)
                } else {
                    self.synthesize(next)
                }
            } else {
                self.finishIfNeeded()
            }
        }
    }
}
