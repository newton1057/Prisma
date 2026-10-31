import Foundation

struct RuntimeInfo: Codable {
    let port: Int
    let token: String
    let pid: Int32
}

struct AppConfig: Codable {
    var port: Int
    var token: String
    var piperPython: String?
    var piperModel: String?
    var projectRoot: String

    static func loadOrCreate() -> AppConfig {
        let fm = FileManager.default
        try? fm.createDirectory(at: AppPaths.appSupport, withIntermediateDirectories: true)
        try? fm.createDirectory(at: AppPaths.temp, withIntermediateDirectories: true)

        var config: AppConfig
        if let data = try? Data(contentsOf: AppPaths.config),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = AppConfig(
                port: 8787,
                token: UUID().uuidString,
                piperPython: nil,
                piperModel: nil,
                projectRoot: AppPaths.defaultProjectRoot.path
            )
        }

        config.resolvePaths()
        config.save()
        return config
    }

    mutating func resolvePaths() {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: projectRoot)

        let pythonCandidates = [
            piperPython,
            root.appendingPathComponent(".venv/bin/python3").path,
            AppPaths.appSupport.appendingPathComponent("venv/bin/python3").path,
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ].compactMap { $0 }

        piperPython = pythonCandidates.first { fm.isExecutableFile(atPath: $0) }

        let modelCandidates = [
            piperModel,
            root.appendingPathComponent("voices/piper/es_MX-claude-high.onnx").path(percentEncoded: false),
            AppPaths.appSupport.appendingPathComponent("voices/es_MX-claude-high.onnx").path(percentEncoded: false)
        ].compactMap { $0 }

        piperModel = modelCandidates.first { fm.fileExists(atPath: $0) }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: AppPaths.config, options: .atomic)
        }
    }

    func writeRuntime() {
        let info = RuntimeInfo(
            port: port,
            token: token,
            pid: ProcessInfo.processInfo.processIdentifier
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(info) {
            try? data.write(to: AppPaths.runtime, options: .atomic)
        }
    }
}

enum AppPaths {
    static let defaultProjectRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/Prisma", isDirectory: true)

    static let appSupport: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Prisma", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var config: URL { appSupport.appendingPathComponent("config.json") }
    static var runtime: URL { appSupport.appendingPathComponent("runtime.json") }
    static var temp: URL { appSupport.appendingPathComponent("tmp", isDirectory: true) }
    static var log: URL { appSupport.appendingPathComponent("prisma.log") }
}
