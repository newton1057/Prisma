import AppKit
import SwiftUI
import UpdateCore

/// App work that must not be interrupted by an update.
@MainActor
enum AppActivity {
    static var running = false
    static var updating = false
}

/// Detects new versions in the bucket, verifies them and replaces the installed app.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateManifest)
        case downloading(UpdateManifest, Double)
        case installing(UpdateManifest)
        case failed(String, UpdateManifest?)
    }

    private struct Problem: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    @Published private(set) var state = State.idle

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    private let installed: URL
    /// Only the packaged app updates: the development copy lives next to Package.swift.
    private let enabled: Bool
    private let channel: URL
    private let log: URL
    private let session: URLSession
    private var observation: NSKeyValueObservation?
    private var watching = false

    init() {
        let bundle = Bundle.main.bundleURL
        installed = bundle
        let packaged = Bundle.main.object(forInfoDictionaryKey: "PrismaUpdatesEnabled") as? Bool == true
        let development = FileManager.default.fileExists(
            atPath: bundle.deletingLastPathComponent().appendingPathComponent("Package.swift").path
        )
        enabled = packaged && !development

        let test = ProcessInfo.processInfo.environment["PRISMA_ACTUALIZACIONES_URL"].flatMap(URL.init(string:))
        channel = test ?? UpdateChannel.base
        log = AppPaths.log

        let configuration = URLSessionConfiguration.ephemeral
        // A cached manifest would hide new versions.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3600
        session = URLSession(configuration: configuration)
    }

    /// Checks at launch and every six hours, because the app can stay open for days.
    func watch() async {
        guard enabled, !watching else { return }
        watching = true
        defer { watching = false }
        while !Task.isCancelled {
            await check()
            try? await Task.sleep(for: .seconds(6 * 60 * 60))
        }
    }

    func check(manually: Bool = false) async {
        guard enabled else {
            if manually { state = .failed("Las actualizaciones solo funcionan en la app instalada.", nil) }
            return
        }
        switch state {
        case .downloading, .installing: return
        default: break
        }
        if manually { state = .checking }
        do {
            let (data, response) = try await session.data(from: channel.appendingPathComponent("latest.json"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Problem("El servidor de actualizaciones no respondió.") }
            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            guard manifest.hasValidSignature() else { throw Problem("La versión publicada no tiene una firma válida.") }
            // A slower check must not overwrite the progress of an update already running.
            switch state {
            case .downloading, .installing: return
            default: break
            }
            if manifest.build > build {
                if state != .available(manifest) { note("versión \(manifest.version) disponible") }
                state = .available(manifest)
            } else {
                note("al día; publicada \(manifest.version)")
                if manually { state = .upToDate }
            }
        } catch {
            note("no se pudo consultar: \(error.localizedDescription)")
            if manually { state = .failed("No se pudo comprobar si hay versiones nuevas. \(error.localizedDescription)", nil) }
        }
    }

    func install(_ manifest: UpdateManifest) {
        if AppActivity.running {
            fail("Espera a que Prisma termine de hablar.", retry: manifest)
            return
        }
        guard !AppActivity.updating else { return }
        if let problem = replacementProblem {
            fail(problem, retry: nil)
            return
        }
        AppActivity.updating = true
        state = .downloading(manifest, 0)
        note("descargando \(manifest.version)")
        Task {
            var workspace: URL?
            do {
                let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installed, create: true)
                workspace = folder
                let package = folder.appendingPathComponent("actualizacion.zip")
                try await download(manifest, to: package)
                state = .installing(manifest)
                let updated = try await Task.detached { try Self.prepare(package, manifest, in: folder) }.value
                try launchInstaller(updated, workspace: folder)
                note("versión \(manifest.version) verificada; reemplazando la app")
                NSApp.terminate(nil)
            } catch {
                if let workspace { try? FileManager.default.removeItem(at: workspace) }
                AppActivity.updating = false
                fail("No se pudo actualizar: \(error.localizedDescription)", retry: manifest)
            }
        }
    }

    func dismiss() { state = .idle }

    func openManualDownload() { NSWorkspace.shared.open(UpdateChannel.manualDownload) }

    private var replacementProblem: String? {
        let writable = FileManager.default.isWritableFile(atPath: installed.deletingLastPathComponent().path)
        guard !writable || installed.path.contains("/AppTranslocation/") else { return nil }
        return "La app no puede reemplazarse desde esta ubicación. Muévela a Aplicaciones o usa el DMG."
    }

    private func fail(_ text: String, retry manifest: UpdateManifest?) {
        note(text)
        state = .failed(text, manifest)
    }

    private func download(_ manifest: UpdateManifest, to destination: URL) async throws {
        let source = channel.appendingPathComponent(manifest.file)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = session.downloadTask(with: source) { temporary, response, error in
                do {
                    if let error { throw error }
                    guard (response as? HTTPURLResponse)?.statusCode == 200, let temporary else {
                        throw Problem("el servidor no entregó la versión nueva.")
                    }
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor in self?.showProgress(fraction, of: manifest) }
            }
            task.resume()
        }
        observation = nil
    }

    private func showProgress(_ fraction: Double, of manifest: UpdateManifest) {
        guard case .downloading(_, let shown) = state, fraction - shown >= 0.01 else { return }
        state = .downloading(manifest, fraction)
    }

    /// Nothing replaces the app without matching what the publisher signed.
    private nonisolated static func prepare(_ package: URL, _ manifest: UpdateManifest, in workspace: URL) throws -> URL {
        let size = try package.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == manifest.size, try sha256Hex(of: package) == manifest.sha256 else {
            throw Problem("el archivo descargado no coincide con la versión publicada.")
        }
        try run("/usr/bin/ditto", ["-x", "-k", package.path, workspace.path], "no se pudo descomprimir la versión nueva.")
        let updated = workspace.appendingPathComponent("Prisma.app")
        let info = NSDictionary(contentsOf: updated.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info?["CFBundleVersion"] as? String == String(manifest.build) else {
            throw Problem("el paquete descargado no es la versión anunciada.")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", updated.path], "la versión nueva no pasó la comprobación de código.")
        // Already verified with our signature: macOS must not ask to approve it again.
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", updated.path], "")
        return updated
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String], _ failure: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Problem(failure) }
    }

    private func launchInstaller(_ updated: URL, workspace: URL) throws {
        let script = workspace.appendingPathComponent("instalar.sh")
        try Self.installer.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), installed.path, updated.path, workspace.path, log.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// The app cannot be replaced while it runs: this script waits for it to close and reopens it.
    /// Checks that it reopened because `open` can exit fine without launching it.
    private nonisolated static let installer = #"""
    #!/bin/sh
    pid=$1 app=$2 nueva=$3 zona=$4 registro=$5
    anota() { printf '%s actualizacion: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$registro" 2>/dev/null; }
    espera=0
    while kill -0 "$pid" 2>/dev/null; do
        espera=$((espera + 1))
        if [ "$espera" -gt 600 ]; then anota "la app no se cerró; se cancela"; rm -rf "$zona"; exit 1; fi
        sleep 0.1
    done
    anterior="$app.anterior"
    rm -rf "$anterior"
    if mv "$app" "$anterior" && mv "$nueva" "$app"; then
        rm -rf "$anterior"
        anota "instalada"
    else
        [ -e "$app" ] || mv "$anterior" "$app"
        anota "no se pudo reemplazar; se conserva la versión anterior"
    fi
    for intento in 1 2 3 4 5; do
        open "$app"
        sleep 2
        if pgrep -f "$app/Contents/MacOS/" >/dev/null; then anota "reabierta"; break; fi
        anota "no reabrió al intento $intento"
    done
    rm -rf "$zona"
    """#

    /// Same format and local time the engine writes in this log.
    private static let logStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private func note(_ text: String) {
        guard enabled else { return }
        let line = Data("\(Self.logStamp.string(from: Date())) actualizacion: \(text)\n".utf8)
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let file = try? FileHandle(forWritingTo: log) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: line)
        } else {
            try? line.write(to: log)
        }
    }
}

/// Notice inside Ajustes. It only appears when there is something to say.
struct UpdateBanner: View {
    @ObservedObject var updater: Updater
    let busy: Bool

    var body: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .checking:
            row("arrow.triangle.2.circlepath", .accentColor, "Buscando actualizaciones", "Consultando la última versión publicada.") {
                ProgressView().controlSize(.small)
            }
        case .upToDate:
            row("checkmark.circle", .accentColor, "Prisma está al día", "Tienes la versión \(updater.version).") {
                Button("Cerrar") { updater.dismiss() }.buttonStyle(.bordered).controlSize(.small)
            }
        case .available(let manifest):
            row("arrow.down.circle", .accentColor, "Versión \(manifest.version) disponible",
                busy ? "Podrás actualizar cuando Prisma termine de hablar." : manifest.notes) {
                Button("Actualizar") { updater.install(manifest) }
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(busy)
            }
        case .downloading(let manifest, let fraction):
            row("arrow.down.circle", .accentColor, "Descargando la versión \(manifest.version)", "\(Int(fraction * 100)) %") {
                ProgressView(value: fraction).frame(width: 120)
            }
        case .installing(let manifest):
            row("checkmark.shield", .accentColor, "Instalando la versión \(manifest.version)", "La app se reiniciará en unos segundos.") {
                ProgressView().controlSize(.small)
            }
        case .failed(let text, let manifest):
            row("exclamationmark.triangle", .orange, "No se completó la actualización", text) {
                if let manifest {
                    Button("Reintentar") { updater.install(manifest) }.buttonStyle(.bordered).controlSize(.small)
                }
                Button("Descargar de GitHub") { updater.openManualDownload() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Cerrar") { updater.dismiss() }.buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private func row(_ icon: String, _ color: Color, _ title: String, _ detail: String, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            actions()
        }
        .padding(.vertical, 2)
    }
}
