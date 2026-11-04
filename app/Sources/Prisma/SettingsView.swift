import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var appState: AppState
    @StateObject private var agents = AgentConnector()

    private static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        Form {
            Section {
                ForEach(agents.connections) { connection in
                    AgentConnectionRow(
                        connection: connection,
                        isWorking: agents.working == connection.kind,
                        onConnect: { agents.connect(connection.kind) },
                        onDisconnect: { agents.disconnect(connection.kind) }
                    )
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .foregroundStyle(.secondary)
                    Text("Solo sesiones locales en este Mac: las sesiones en la nube o en otro equipo no ejecutan estos hooks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !agents.jqAvailable {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Falta jq, que los hooks usan para leer los eventos. Instálalo con: brew install jq")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(agents.lastWarnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Agentes")
            } footer: {
                Text("Conecta Prisma con cada agente desde la app. Instala los hooks y el plugin en tu carpeta de usuario, sin depender del repositorio. Reinicia las sesiones abiertas para que tomen los hooks nuevos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            Section("Audio de fondo") {
                Toggle("Bajar música y videos mientras Prisma habla", isOn: $settings.duckAudio)

                if settings.duckAudio {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Volumen mientras hablo")
                            Spacer()
                            Text("\(Int(settings.duckLevel * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.duckLevel, in: 0.15...0.7, step: 0.05)
                    }

                    Text("Prisma baja el volumen del Mac y sube el nivel de su propia voz para quedar en primer plano. Al terminar, el volumen vuelve solo a su nivel anterior.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Animación") {
                Picker("Pantalla", selection: $settings.targetDisplay) {
                    ForEach(settings.displayOptions()) { option in
                        Text(option.title).tag(option.id)
                    }
                }

                Picker("Atajo para cambiar pantalla", selection: $settings.screenShortcut) {
                    ForEach(ScreenShortcut.allCases) { shortcut in
                        Text(shortcut.title).tag(shortcut)
                    }
                }

                Picker("Posición", selection: $settings.position) {
                    ForEach(OverlayPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }

                Picker("Atajo para cambiar posición", selection: $settings.positionShortcut) {
                    ForEach(PositionShortcut.allCases) { shortcut in
                        Text(shortcut.title).tag(shortcut)
                    }
                }

                Toggle("Mostrar el orbe mientras el agente piensa", isOn: $settings.showThinking)
                Toggle("Mostrar información de la sesión al pasar el cursor", isOn: $settings.showHoverInfo)
                Toggle("Mantener el orbe un momento al terminar", isOn: $settings.stayVisible)
            }

            Section("Color del halo por agente") {
                HaloThemeRow(title: "Codex", selection: $settings.codexTheme)
                HaloThemeRow(title: "Claude Code", selection: $settings.claudeTheme)
                HaloThemeRow(title: "OpenCode", selection: $settings.openCodeTheme)
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
                    Text("Prisma \(Self.shortVersion)")
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
        .frame(width: 580, height: 880)
        .onAppear { agents.refresh() }
    }
}

private struct AgentConnectionRow: View {
    let connection: AgentConnection
    let isWorking: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    private var statusColor: Color {
        switch connection.state {
        case .connected: return .green
        case .incomplete: return .orange
        case .agentMissing: return .gray
        case .failed: return .red
        case .working: return .blue
        case .disconnected: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.kind.title)
                Text(connection.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isWorking {
                ProgressView()
                    .controlSize(.small)
            } else if connection.state.isConnected {
                Button("Reconectar", action: onConnect)
                Button("Desconectar", action: onDisconnect)
            } else if case .agentMissing = connection.state {
                Text("Instala su CLI para conectarlo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Conectar", action: onConnect)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HaloThemeRow: View {
    let title: String
    @Binding var selection: HaloTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker(title, selection: $selection) {
                ForEach(HaloTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }

            HStack(spacing: 9) {
                ForEach(HaloTheme.allCases) { theme in
                    let pal = theme.palette
                    let selected = selection == theme
                    Button {
                        selection = theme
                    } label: {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [
                                        Color(red: pal.lowerBright.x, green: pal.lowerBright.y, blue: pal.lowerBright.z),
                                        Color(red: pal.lowerMid.x, green: pal.lowerMid.y, blue: pal.lowerMid.z),
                                        Color(red: pal.upperMid.x, green: pal.upperMid.y, blue: pal.upperMid.z),
                                        Color(red: pal.upperBright.x, green: pal.upperBright.y, blue: pal.upperBright.z),
                                        Color(red: pal.lowerBright.x, green: pal.lowerBright.y, blue: pal.lowerBright.z)
                                    ],
                                    center: .center
                                )
                            )
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(selected ? Color.primary : Color.white.opacity(0.28), lineWidth: selected ? 2.2 : 1.0)
                            )
                            .scaleEffect(selected ? 1.14 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .help(theme.title)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
