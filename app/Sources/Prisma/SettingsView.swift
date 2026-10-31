import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Voz") {
                Picker("Motor", selection: $settings.voice) {
                    ForEach(VoiceEngine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }

                if settings.voice == .edge {
                    Picker("Voz Neural", selection: $settings.edgeVoice) {
                        ForEach(EdgeVoiceOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                }

                Picker("Lectura", selection: $settings.mode) {
                    ForEach(ReadMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Velocidad")
                        Spacer()
                        Text(String(format: "%.2fx", settings.speed))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.speed, in: 0.8...1.2, step: 0.05)
                }

                HStack(spacing: 10) {
                    Button("Probar voz") {
                        appState.testVoice()
                    }
                    Button("Detener") {
                        appState.stopSpeaking()
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(appState.piperReady ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(appState.piperReady ? "Piper listo" : "Piper no encontrado")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Animación") {
                Picker("Posición", selection: $settings.position) {
                    ForEach(OverlayPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }

                Toggle("Mantener el orbe un momento al terminar", isOn: $settings.stayVisible)
            }

            Section("Servidor local") {
                HStack(spacing: 7) {
                    Circle()
                        .fill(appState.serverRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(appState.serverStatus)
                        .font(.callout)
                    Spacer()
                }

                Text("Los plugins de Codex, Claude Code y OpenCode llaman a esta app en 127.0.0.1. Solo acepta peticiones con el token local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Rutas de Piper") {
                TextField("Python del entorno", text: $settings.piperPythonPath)
                    .textFieldStyle(.roundedBorder)
                TextField("Modelo .onnx", text: $settings.piperModelPath)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Abrir datos") {
                        NSWorkspace.shared.open(AppPaths.appSupport)
                    }
                    Button("Abrir proyecto") {
                        NSWorkspace.shared.open(AppPaths.defaultProjectRoot)
                    }
                    Spacer()
                }
            }

            Section {
                HStack {
                    Text("Prisma 1.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Salir de Prisma") {
                        appState.quit()
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 660)
    }
}
