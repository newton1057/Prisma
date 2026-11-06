import Foundation
import AVFoundation
import AudioToolbox
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
            ("\\bMuse\\s+Code\\b", "Mius Coud"),
            ("\\bAntigravity\\b", "Antigráviti"),
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
    private var overlay: OverlayController
    private let ducker = SystemAudioDucker()

    private var session: SpeechSession?
    private var appleSynth: AVSpeechSynthesizer?
    private var appleDelegate: AppleSpeechDelegate?
    private var appleMeterTimer: Timer?
    private var lastSignature: String?
    private var lastSignatureTime: Date?
    var onFinish: (() -> Void)?

    init(config: AppConfig, settings: SettingsStore, overlay: OverlayController) {
        self.config = config
        self.settings = settings
        self.overlay = overlay
    }

    func selectOverlay(_ overlay: OverlayController) {
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

    @discardableResult func speak(
        text: String,
        mode: ReadMode? = nil,
        cwd: String? = nil,
        sessionID: String? = nil,
        engineOverride: String? = nil,
        voiceOverride: String? = nil
    ) -> Bool {
        let signature = "\(sessionID ?? "")|\(engineOverride ?? "")|\(voiceOverride ?? "")|\(text)"
        if signature == lastSignature,
           let lastSignatureTime,
           Date().timeIntervalSince(lastSignatureTime) < 2.0 {
            return false
        }
        lastSignature = signature
        lastSignatureTime = Date()

        stopInternal(restoreDuck: false)

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
        guard !prepared.isEmpty else {
            ducker.restore()
            return false
        }

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
        return true
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
            duckBoost: { [weak self] in self?.startDuckingForVoice() ?? 0 },
            duckKeepAlive: { [weak self] in self?.ducker.keepAlive() },
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

    /// Called right before the first chunk starts playing, so music is not
    /// ducked while edge-tts is still synthesizing.
    private func startDuckingForVoice() -> Double {
        guard settings.duckAudio else {
            ducker.restore()
            return 0
        }
        return ducker.duck(to: settings.duckLevel)
    }

    func stop() {
        stopInternal(restoreDuck: true)
    }

    func shutdown() {
        stopInternal(restoreDuck: false)
        ducker.restoreImmediately()
    }

    private func stopInternal(restoreDuck: Bool) {
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
        if restoreDuck {
            ducker.restore()
        }
    }

    private func finish() {
        session = nil
        appleMeterTimer?.invalidate()
        appleMeterTimer = nil
        ducker.restore()
        overlay.setProgress(1)
        overlay.setAudioLevel(0)
        overlay.setSpeaking(false)
        overlay.hide(after: settings.stayVisible ? 1.2 : 0.2)
        onFinish?()
    }

    private func speakWithApple(_ text: String) {
        // AVSpeechSynthesizer cannot be boosted, so duck less aggressively to
        // keep the fallback voice intelligible.
        if settings.duckAudio {
            _ = ducker.duck(to: max(0.65, settings.duckLevel))
        } else {
            ducker.restore()
        }

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
    private let duckBoost: () -> Double
    private let duckKeepAlive: () -> Void
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

    private let engine = AVAudioEngine()
    private let limiter: AVAudioUnitEffect
    private var playerNode: AVAudioPlayerNode?
    private var pendingNode: AVAudioPlayerNode?
    private var currentFile: AVAudioFile?
    private var playbackWorkItem: DispatchWorkItem?
    private var graphReady = false
    private var meterTapInstalled = false
    private var lastMeterDispatch: CFTimeInterval = 0
    private var smoothedLevel: Double = 0

    init(
        text: String,
        backend: Backend,
        speed: Double,
        overlay: OverlayController,
        duckBoost: @escaping () -> Double,
        duckKeepAlive: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (Bool) -> Void
    ) {
        self.chunks = TextPreparer.chunks(text)
        self.backend = backend
        self.speed = speed
        self.overlay = overlay
        self.duckBoost = duckBoost
        self.duckKeepAlive = duckKeepAlive
        self.onFinish = onFinish
        self.onError = onError

        var description = AudioComponentDescription()
        description.componentType = kAudioUnitType_Effect
        description.componentSubType = kAudioUnitSubType_PeakLimiter
        description.componentManufacturer = kAudioUnitManufacturer_Apple
        description.componentFlags = 0
        description.componentFlagsMask = 0
        self.limiter = AVAudioUnitEffect(audioComponentDescription: description)

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
        isPlaying = false
        teardownEngine()
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
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat

            if !graphReady {
                engine.attach(limiter)
                engine.connect(limiter, to: engine.mainMixerNode, format: format)
                installMeterTap()
                graphReady = true
            }

            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: limiter, format: format)

            if !engine.isRunning {
                try engine.start()
            }

            var preRoll: TimeInterval = 0
            if !didStartPlayback {
                let boost = duckBoost()
                applyLimiterGain(boost)
                // Give the system volume ramp a head start so the first word
                // does not play at full volume with the voice already boosted.
                if boost > 0.1 {
                    preRoll = 0.32
                }
            }

            if preRoll > 0 {
                pendingNode = node
                let work = DispatchWorkItem { [weak self] in
                    self?.beginPlayback(node: node, file: file, index: index)
                }
                playbackWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + preRoll, execute: work)
            } else {
                beginPlayback(node: node, file: file, index: index)
            }
        } catch {
            onError(didStartPlayback)
        }
    }

    private func beginPlayback(node: AVAudioPlayerNode, file: AVAudioFile, index: Int) {
        guard !isCancelled, !isPlaying, !didFinish, node.engine != nil else {
            detach(node: node)
            return
        }
        pendingNode = nil
        playbackWorkItem = nil

        node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                self?.chunkFinished(index)
            }
        }
        node.play()

        playerNode = node
        currentFile = file
        isPlaying = true
        currentIndex = index
        didStartPlayback = true
        duckKeepAlive()

        let progress = Double(index) / Double(max(1, chunks.count))
        overlay?.setProgress(progress)
        overlay?.setCaption("PRISMA")

        if index + 1 < chunks.count, audioURLs[index + 1] == nil {
            synthesize(index + 1)
        }
        if index + 2 < chunks.count, audioURLs[index + 2] == nil {
            synthesize(index + 2)
        }
    }

    private func applyLimiterGain(_ decibels: Double) {
        let preGain = Float(min(12.0, max(0.0, decibels)))
        let unit = limiter.audioUnit
        AudioUnitSetParameter(unit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.006, 0)
        AudioUnitSetParameter(unit, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.05, 0)
        AudioUnitSetParameter(unit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, preGain, 0)
    }

    private func installMeterTap() {
        guard !meterTapInstalled else { return }
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.processMeter(buffer)
        }
        meterTapInstalled = true
    }

    private func processMeter(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return }

        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frames {
                sum += samples[frame] * samples[frame]
            }
        }

        let rms = sqrt(sum / Float(frames * channelCount))
        let db = 20.0 * log10(max(Double(rms), 0.00001))
        let normalized = max(0.0, min(1.0, (db + 45.0) / 35.0))
        let level = pow(normalized, 1.2)

        let now = CACurrentMediaTime()
        guard now - lastMeterDispatch >= 1.0 / 30.0 else { return }
        lastMeterDispatch = now

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isCancelled, self.isPlaying else { return }
            if level > self.smoothedLevel {
                self.smoothedLevel = self.smoothedLevel * 0.32 + level * 0.68
            } else {
                self.smoothedLevel = self.smoothedLevel * 0.72 + level * 0.28
            }
            self.overlay?.setAudioLevel(self.smoothedLevel)
        }
    }

    private func stopMetering() {
        if meterTapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            meterTapInstalled = false
        }
        smoothedLevel = 0
        overlay?.setAudioLevel(0)
    }

    private func finishIfNeeded() {
        guard !didFinish else { return }
        didFinish = true
        isPlaying = false
        teardownEngine()
        cleanupFiles()
        onFinish()
    }

    private func chunkFinished(_ index: Int) {
        guard !isCancelled, currentIndex == index else { return }
        isPlaying = false
        detachPlayerNode()
        smoothedLevel = 0
        overlay?.setAudioLevel(0)

        let next = index + 1
        if next < chunks.count {
            // Advance currentIndex BEFORE checking audioURLs[next] so if `next` is still
            // synthesizing, its completion handler sees `self.currentIndex == indexCopy` and plays it!
            currentIndex = next
            if audioURLs[next] != nil {
                play(next)
            } else {
                synthesize(next)
            }
        } else {
            finishIfNeeded()
        }
    }

    private func detachPlayerNode() {
        guard let node = playerNode else { return }
        detach(node: node)
        playerNode = nil
        currentFile = nil
    }

    private func detach(node: AVAudioPlayerNode) {
        guard node.engine != nil else { return }
        node.stop()
        engine.disconnectNodeOutput(node)
        engine.detach(node)
    }

    private func teardownEngine() {
        playbackWorkItem?.cancel()
        playbackWorkItem = nil
        if let pending = pendingNode {
            detach(node: pending)
            pendingNode = nil
        }
        stopMetering()
        detachPlayerNode()
        if engine.isRunning {
            engine.stop()
        }
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
