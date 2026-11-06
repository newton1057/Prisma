import Foundation

// MARK: - Agents

enum AgentKind: String, CaseIterable, Identifiable {
    case codex
    case claudeCode = "claude-code"
    case openCode = "opencode"
    case muse
    case antigravity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .openCode: return "OpenCode"
        case .muse: return "Muse Code"
        case .antigravity: return "Antigravity"
        }
    }

    var executable: String {
        switch self {
        case .codex: return "codex"
        case .claudeCode: return "claude"
        case .openCode: return "opencode"
        case .muse: return "muse"
        case .antigravity: return "agy"
        }
    }
}

enum ConnectionState: Equatable {
    case connected
    case incomplete
    case disconnected
    case agentMissing
    case working
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct AgentConnection: Identifiable, Equatable {
    let kind: AgentKind
    var state: ConnectionState
    var detail: String
    var id: String { kind.rawValue }
}

// MARK: - Paths

struct AgentPaths {
    let home: URL
    let support: URL
    let codexHome: URL
    /// `$XDG_CONFIG_HOME` when set, `~/.config` otherwise, as Muse Code reads it.
    let configHome: URL

    init(home: URL, support: URL, codexHome: URL, configHome: URL? = nil) {
        self.home = home
        self.support = support
        self.codexHome = codexHome
        if let configHome {
            self.configHome = configHome
        } else {
            let custom = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let custom, !custom.isEmpty {
                self.configHome = URL(fileURLWithPath: custom, isDirectory: true)
            } else {
                self.configHome = home.appendingPathComponent(".config", isDirectory: true)
            }
        }
    }

    static func live() -> AgentPaths {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let customCodex = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let codexHome: URL
        if let customCodex, !customCodex.isEmpty {
            codexHome = URL(fileURLWithPath: customCodex, isDirectory: true)
        } else {
            codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        }
        return AgentPaths(home: home, support: AppPaths.appSupport, codexHome: codexHome)
    }

    var dist: URL { support.appendingPathComponent("plugin-dist", isDirectory: true) }
    var claudeHome: URL { home.appendingPathComponent(".claude", isDirectory: true) }
    var openCodeConfig: URL { home.appendingPathComponent(".config/opencode", isDirectory: true) }

    var codexHooks: URL { codexHome.appendingPathComponent("hooks.json") }
    var codexConfig: URL { codexHome.appendingPathComponent("config.toml") }
    var codexAgents: URL { codexHome.appendingPathComponent("AGENTS.md") }

    var claudeAgents: URL { claudeHome.appendingPathComponent("CLAUDE.md") }
    var claudeSettings: URL { claudeHome.appendingPathComponent("settings.json") }
    var claudeKnownMarketplaces: URL { claudeHome.appendingPathComponent("plugins/known_marketplaces.json") }
    var claudeInstalledPlugins: URL { claudeHome.appendingPathComponent("plugins/installed_plugins.json") }

    var openCodePlugin: URL { openCodeConfig.appendingPathComponent("plugins/prisma.ts") }
    var openCodeSkill: URL { openCodeConfig.appendingPathComponent("skills/prisma/SKILL.md") }

    var museConfig: URL { configHome.appendingPathComponent("muse", isDirectory: true) }
    var museSettings: URL { museConfig.appendingPathComponent("settings.json") }
    var museAgents: URL { museConfig.appendingPathComponent("AGENTS.md") }

    /// Antigravity shares one customization directory across its surfaces.
    var antigravityConfig: URL { home.appendingPathComponent(".gemini/config", isDirectory: true) }
    var antigravityHooks: URL { antigravityConfig.appendingPathComponent("hooks.json") }
    var antigravityAgents: URL { antigravityConfig.appendingPathComponent("AGENTS.md") }
}

// MARK: - Shell

struct CommandResult {
    let status: Int32
    let output: String
    var succeeded: Bool { status == 0 }
}

enum CommandError: LocalizedError {
    case timedOut(String)
    case failed(String, String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let command):
            return "El comando \(command) tardó demasiado y se canceló."
        case .failed(let command, let output):
            let tail = output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(400)
            return tail.isEmpty ? "El comando \(command) falló." : "El comando \(command) falló: \(tail)"
        }
    }
}

enum Shell {
    /// Runs a login shell so the PATH is the one the user sees in Terminal:
    /// Finder launches Prisma with a minimal PATH that misses `~/.local/bin`.
    static func run(_ tool: String, _ args: [String], timeout: TimeInterval = 90) throws -> CommandResult {
        let command = ([tool] + args).map(quoted).joined(separator: " ")
        return try runShell(command, timeout: timeout)
    }

    static func runShell(_ command: String, timeout: TimeInterval = 90) throws -> CommandResult {
        let fm = FileManager.default
        let log = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prisma-command-\(UUID().uuidString).log")
        fm.createFile(atPath: log.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: log) else {
            throw CommandError.failed(command, "No pude crear el archivo de salida.")
        }
        defer {
            try? handle.close()
            try? fm.removeItem(at: log)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment

        do {
            try process.run()
        } catch {
            throw CommandError.failed(command, error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw CommandError.timedOut(command)
        }
        process.waitUntilExit()

        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return CommandResult(status: process.terminationStatus, output: output)
    }

    static func exists(_ tool: String) -> Bool {
        guard let result = try? runShell("command -v \(quoted(tool))", timeout: 15) else { return false }
        return result.succeeded && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Installer

struct AgentInstaller {
    struct HookSpec {
        let event: String
        let command: String
        let timeout: Int
        let matcher: String?
        /// Muse Code only admits cancellation hooks that run detached.
        var isAsync: Bool = false
    }

    let paths: AgentPaths
    var runCommand: (String, [String]) throws -> CommandResult
    var trustCodexHooks: (URL, URL) -> Bool
    var resourceRoot: () throws -> URL

    init(
        paths: AgentPaths,
        runCommand: @escaping (String, [String]) throws -> CommandResult = { tool, args in
            try Shell.run(tool, args)
        },
        trustCodexHooks: @escaping (URL, URL) -> Bool = { hooksFile, cwd in
            CodexHookTrust.apply(hooksFile: hooksFile, cwd: cwd)
        },
        resourceRoot: (() throws -> URL)? = nil
    ) {
        self.paths = paths
        self.runCommand = runCommand
        self.trustCodexHooks = trustCodexHooks
        self.resourceRoot = resourceRoot ?? { try AgentInstaller.resourceRoot() }
    }

    // MARK: Sources

    static func resourceRoot() throws -> URL {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("plugin-dist", isDirectory: true),
           fm.fileExists(atPath: bundled.appendingPathComponent("plugin/plugin.json").path) {
            return bundled
        }
        let repo = AppPaths.defaultProjectRoot
        if fm.fileExists(atPath: repo.appendingPathComponent("plugin/plugin.json").path) {
            return repo
        }
        throw CommandError.failed("Prisma", "No encontré los archivos de integración en la app.")
    }

    // MARK: Status

    func status(for kind: AgentKind, cliAvailable: Bool) -> AgentConnection {
        guard cliAvailable else {
            return AgentConnection(
                kind: kind,
                state: .agentMissing,
                detail: "No encontrado en este Mac"
            )
        }

        switch kind {
        case .codex:
            var missing: [String] = []
            let hooksInstalled = codexHooksInstalled()
            let pluginInstalled = codexPluginInstalled()
            if !hooksInstalled { missing.append("hooks") }
            if !pluginInstalled { missing.append("plugin") }
            if hooksInstalled && !codexHooksTrusted() { missing.append("confianza") }
            if missing.isEmpty {
                return AgentConnection(kind: kind, state: .connected, detail: "Conectado")
            }
            if !hooksInstalled && !pluginInstalled {
                return AgentConnection(kind: kind, state: .disconnected, detail: "No conectado")
            }
            return AgentConnection(kind: kind, state: .incomplete, detail: "Falta: \(missing.joined(separator: ", "))")

        case .claudeCode:
            var missing: [String] = []
            if !claudePluginInstalled() { missing.append("plugin") }
            if !claudePluginEnabled() { missing.append("activación") }
            if !claudeMarketplaceInstalled() { missing.append("marketplace") }
            if missing.isEmpty {
                return AgentConnection(kind: kind, state: .connected, detail: "Conectado")
            }
            if missing.count == 3 {
                return AgentConnection(kind: kind, state: .disconnected, detail: "No conectado")
            }
            return AgentConnection(kind: kind, state: .incomplete, detail: "Falta: \(missing.joined(separator: ", "))")

        case .openCode:
            let plugin = FileManager.default.contents(atPath: paths.openCodePlugin.path)
            let skillExists = FileManager.default.fileExists(atPath: paths.openCodeSkill.path)
            if plugin == nil && !skillExists {
                return AgentConnection(kind: kind, state: .disconnected, detail: "No conectado")
            }
            if plugin == nil {
                return AgentConnection(kind: kind, state: .incomplete, detail: "Falta: plugin")
            }
            if !skillExists {
                return AgentConnection(kind: kind, state: .incomplete, detail: "Falta: skill")
            }
            if let expected = try? Data(contentsOf: paths.dist.appendingPathComponent("plugin/opencode/prisma.ts")),
               expected != plugin {
                return AgentConnection(kind: kind, state: .incomplete, detail: "Plugin desactualizado")
            }
            return AgentConnection(kind: kind, state: .connected, detail: "Conectado")

        case .muse:
            let hooksInstalled = museHooksInstalled()
            let instructed = instructionInstalled(paths.museAgents)
            if hooksInstalled && instructed {
                return AgentConnection(kind: kind, state: .connected, detail: "Conectado")
            }
            if !hooksInstalled && !instructed {
                return AgentConnection(kind: kind, state: .disconnected, detail: "No conectado")
            }
            let missing = (hooksInstalled ? [] : ["hooks"]) + (instructed ? [] : ["instrucciones"])
            return AgentConnection(kind: kind, state: .incomplete, detail: "Falta: \(missing.joined(separator: ", "))")

        case .antigravity:
            let hooksInstalled = antigravityHooksInstalled()
            let instructed = instructionInstalled(paths.antigravityAgents)
            if hooksInstalled && instructed {
                return AgentConnection(kind: kind, state: .connected, detail: "Conectado")
            }
            if !hooksInstalled && !instructed {
                return AgentConnection(kind: kind, state: .disconnected, detail: "No conectado")
            }
            let missing = (hooksInstalled ? [] : ["hooks"]) + (instructed ? [] : ["instrucciones"])
            return AgentConnection(kind: kind, state: .incomplete, detail: "Falta: \(missing.joined(separator: ", "))")
        }
    }

    func instructionInstalled(_ file: URL) -> Bool {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return contents.contains("<ForPrisma>")
    }

    func codexHooksInstalled() -> Bool {
        guard let root = readJSON(paths.codexHooks),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return codexSpecs().allSatisfy { spec in
            guard let groups = hooks[spec.event] as? [[String: Any]] else { return false }
            return groups.contains { group in
                let entries = group["hooks"] as? [[String: Any]] ?? []
                return entries.contains { ($0["command"] as? String) == spec.command }
            }
        }
    }

    func codexPluginInstalled() -> Bool {
        guard let config = try? String(contentsOf: paths.codexConfig, encoding: .utf8) else { return false }
        let pluginEntry = config.contains("[plugins.\"prisma@prisma-local\"]")
        let cache = paths.codexHome.appendingPathComponent("plugins/cache/prisma-local/prisma")
        let hasCache = (try? FileManager.default.contentsOfDirectory(atPath: cache.path))?.isEmpty == false
        return pluginEntry && hasCache
    }

    func codexHooksTrusted() -> Bool {
        guard let config = try? String(contentsOf: paths.codexConfig, encoding: .utf8) else { return false }
        let key = canonical(paths.codexHooks) + ":stop:0:0"
        return config.contains(key)
    }

    func claudeMarketplaceInstalled() -> Bool {
        guard let root = readJSON(paths.claudeKnownMarketplaces),
              let entry = root["prisma-local"] as? [String: Any],
              let location = entry["installLocation"] as? String else { return false }
        // Accept any marketplace root that holds our plugin: an install made by
        // install.sh points at the repository, the app points at its own copy.
        let plugin = URL(fileURLWithPath: location).appendingPathComponent("plugin/plugin.json")
        return FileManager.default.fileExists(atPath: plugin.path)
    }

    func claudePluginInstalled() -> Bool {
        guard let root = readJSON(paths.claudeInstalledPlugins),
              let plugins = root["plugins"] as? [String: Any] else { return false }
        return plugins["prisma@prisma-local"] != nil
    }

    func claudePluginEnabled() -> Bool {
        guard let root = readJSON(paths.claudeSettings),
              let enabled = root["enabledPlugins"] as? [String: Any] else { return false }
        return enabled["prisma@prisma-local"] as? Bool == true
    }

    // MARK: Install

    @discardableResult
    func install(_ kind: AgentKind) throws -> [String] {
        try stageResources()
        try installScripts()

        switch kind {
        case .codex: return try installCodex()
        case .claudeCode: return try installClaude()
        case .openCode: return try installOpenCode()
        case .muse: return try installMuse()
        case .antigravity: return try installAntigravity()
        }
    }

    private func installCodex() throws -> [String] {
        var warnings: [String] = []
        try appendAgentsBlock(to: paths.codexAgents, replaceShortFile: true)
        try writeCodexHooks()

        _ = try? runCommand("codex", ["plugin", "marketplace", "remove", "prisma-local"])
        let addedMarketplace = try runCommand("codex", ["plugin", "marketplace", "add", paths.dist.path])
        guard addedMarketplace.succeeded else {
            throw CommandError.failed("codex plugin marketplace add", addedMarketplace.output)
        }
        _ = try? runCommand("codex", ["plugin", "remove", "prisma@prisma-local"])
        let addedPlugin = try runCommand("codex", ["plugin", "add", "prisma@prisma-local"])
        guard addedPlugin.succeeded else {
            throw CommandError.failed("codex plugin add", addedPlugin.output)
        }

        if !trustCodexHooks(paths.codexHooks, paths.dist) {
            warnings.append("No pude marcar los hooks como confiables. Abre Codex y acéptalos cuando lo pregunte.")
        }
        return warnings
    }

    private func installClaude() throws -> [String] {
        try appendAgentsBlock(to: paths.claudeAgents, replaceShortFile: false)

        _ = try? runCommand("claude", ["plugin", "marketplace", "remove", "prisma-local"])
        let addedMarketplace = try runCommand("claude", ["plugin", "marketplace", "add", paths.dist.path])
        guard addedMarketplace.succeeded else {
            throw CommandError.failed("claude plugin marketplace add", addedMarketplace.output)
        }
        _ = try? runCommand("claude", ["plugin", "uninstall", "prisma@prisma-local"])
        let installed = try runCommand("claude", ["plugin", "install", "prisma@prisma-local"])
        guard installed.succeeded else {
            throw CommandError.failed("claude plugin install", installed.output)
        }
        _ = try? runCommand("claude", ["plugin", "enable", "prisma@prisma-local"])
        return []
    }

    private func installOpenCode() throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(
            at: paths.openCodePlugin.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: paths.openCodeSkill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let pluginSource = paths.dist.appendingPathComponent("plugin/opencode/prisma.ts")
        let skillSource = paths.dist.appendingPathComponent("plugin/skills/prisma/SKILL.md")
        try? fm.removeItem(at: paths.openCodePlugin)
        try? fm.removeItem(at: paths.openCodeSkill)
        try fm.copyItem(at: pluginSource, to: paths.openCodePlugin)
        try fm.copyItem(at: skillSource, to: paths.openCodeSkill)

        if Shell.exists("opencode") {
            _ = try? runCommand("opencode", ["reload"])
        }
        return []
    }

    /// Muse Code reads user hooks and user rules from its own config directory;
    /// unlike project hooks, they need no workspace trust step.
    private func installMuse() throws -> [String] {
        try appendAgentsBlock(to: paths.museAgents, replaceShortFile: false)
        try writeMuseHooks()
        return []
    }

    /// Antigravity shares one hooks.json and one AGENTS.md across its app, CLI
    /// and IDE; the "prisma" entry keeps its own events so other hooks survive.
    private func installAntigravity() throws -> [String] {
        try appendAgentsBlock(to: paths.antigravityAgents, replaceShortFile: false)
        try writeAntigravityHooks()
        return []
    }

    // MARK: Remove

    func remove(_ kind: AgentKind) throws {
        switch kind {
        case .codex:
            removeCodexHooks()
            _ = try? runCommand("codex", ["plugin", "remove", "prisma@prisma-local"])
            _ = try? runCommand("codex", ["plugin", "marketplace", "remove", "prisma-local"])
            removeAgentsBlock(from: paths.codexAgents)

        case .claudeCode:
            _ = try? runCommand("claude", ["plugin", "disable", "prisma@prisma-local"])
            _ = try? runCommand("claude", ["plugin", "uninstall", "prisma@prisma-local"])
            _ = try? runCommand("claude", ["plugin", "marketplace", "remove", "prisma-local"])
            removeAgentsBlock(from: paths.claudeAgents)

        case .openCode:
            try? FileManager.default.removeItem(at: paths.openCodePlugin)
            try? FileManager.default.removeItem(at: paths.openCodeSkill)
            if Shell.exists("opencode") {
                _ = try? runCommand("opencode", ["reload"])
            }

        case .muse:
            removeMuseHooks()
            removeAgentsBlock(from: paths.museAgents)

        case .antigravity:
            removeAntigravityHooks()
            removeAgentsBlock(from: paths.antigravityAgents)
        }
    }

    // MARK: Hooks

    func codexSpecs() -> [HookSpec] {
        let stop = "bash \"\(paths.support.path)/on_stop.sh\""
        let turn = "bash \"\(paths.support.path)/on_turn.sh\" codex"
        return [
            HookSpec(event: "UserPromptSubmit", command: turn, timeout: 10, matcher: nil),
            HookSpec(event: "Interrupt", command: turn, timeout: 3, matcher: nil),
            HookSpec(event: "SessionStart", command: turn, timeout: 10, matcher: nil),
            HookSpec(event: "SessionEnd", command: turn, timeout: 3, matcher: nil),
            HookSpec(event: "Stop", command: stop, timeout: 10, matcher: nil),
            HookSpec(
                event: "PreToolUse",
                command: stop,
                timeout: 10,
                matcher: "AskUserQuestion|request_user_input|request_user_input_async|send_user_message_async|send_message_to_user_async|question"
            ),
            HookSpec(event: "PermissionRequest", command: stop, timeout: 10, matcher: nil)
        ]
    }

    func writeCodexHooks() throws {
        var root = readJSON(paths.codexHooks) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for spec in codexSpecs() {
            var groups = hooks[spec.event] as? [[String: Any]] ?? []
            groups = groups.compactMap { group in
                var group = group
                var entries = group["hooks"] as? [[String: Any]] ?? []
                entries.removeAll { isPrismaHook($0) }
                guard !entries.isEmpty else { return nil }
                group["hooks"] = entries
                return group
            }

            let entry: [String: Any] = [
                "type": "command",
                "command": spec.command,
                "timeout": spec.timeout,
                "statusMessage": "Prisma"
            ]
            var group: [String: Any] = ["hooks": [entry]]
            if let matcher = spec.matcher {
                group["matcher"] = matcher
            }
            groups.append(group)
            hooks[spec.event] = groups
        }

        root["hooks"] = hooks
        try writeJSON(root, to: paths.codexHooks)
    }

    func removeCodexHooks() {
        guard var root = readJSON(paths.codexHooks),
              var hooks = root["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups = groups.compactMap { group in
                var group = group
                var entries = group["hooks"] as? [[String: Any]] ?? []
                entries.removeAll { isPrismaHook($0) }
                guard !entries.isEmpty else { return nil }
                group["hooks"] = entries
                return group
            }
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        if hooks.isEmpty {
            try? FileManager.default.removeItem(at: paths.codexHooks)
        } else {
            root["hooks"] = hooks
            try? writeJSON(root, to: paths.codexHooks)
        }
    }

    func isPrismaHook(_ entry: [String: Any]) -> Bool {
        let command = entry["command"] as? String ?? ""
        let status = entry["statusMessage"] as? String
        return command.contains("Application Support/Prisma/on_")
            || command.contains("Application Support/CodexVoz/")
            || status == "Prisma"
            || status == "CodexVoz"
    }

    // MARK: Muse Code

    /// Muse Code accepts the same event names it documents for its hooks; the
    /// Cancellation hook must declare `async: true` or the whole entry is skipped.
    func museSpecs() -> [HookSpec] {
        let turn = "bash \"\(paths.support.path)/on_turn.sh\" muse"
        let stop = "bash \"\(paths.support.path)/on_stop.sh\" muse"
        return [
            HookSpec(event: "SessionStart", command: turn, timeout: 10, matcher: nil),
            HookSpec(event: "UserPromptSubmit", command: turn, timeout: 10, matcher: nil),
            HookSpec(event: "Interrupt", command: turn, timeout: 3, matcher: nil, isAsync: true),
            HookSpec(event: "StopFailure", command: turn, timeout: 3, matcher: nil),
            HookSpec(event: "SessionEnd", command: turn, timeout: 3, matcher: nil),
            HookSpec(event: "Stop", command: stop, timeout: 10, matcher: nil),
            HookSpec(event: "PermissionRequest", command: stop, timeout: 10, matcher: nil),
            HookSpec(
                event: "PreToolUse",
                command: stop,
                timeout: 10,
                matcher: "request_user_input|request_user_input_async"
            )
        ]
    }

    func museHooksInstalled() -> Bool {
        guard let root = readJSON(paths.museSettings),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return museSpecs().allSatisfy { spec in
            guard let groups = hooks[spec.event] as? [[String: Any]] else { return false }
            return groups.contains { group in
                let entries = group["hooks"] as? [[String: Any]] ?? []
                return entries.contains { ($0["command"] as? String) == spec.command }
            }
        }
    }

    func writeMuseHooks() throws {
        var root = readJSON(paths.museSettings) ?? [:]
        if root["schema_version"] == nil { root["schema_version"] = 1 }
        try backup(paths.museSettings)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for spec in museSpecs() {
            var groups = hooks[spec.event] as? [[String: Any]] ?? []
            groups = groups.compactMap { group in
                var group = group
                var entries = group["hooks"] as? [[String: Any]] ?? []
                entries.removeAll { isPrismaHook($0) }
                guard !entries.isEmpty else { return nil }
                group["hooks"] = entries
                return group
            }

            var entry: [String: Any] = [
                "type": "command",
                "command": spec.command,
                "timeout": spec.timeout,
                "statusMessage": "Prisma"
            ]
            if spec.isAsync { entry["async"] = true }
            var group: [String: Any] = ["hooks": [entry]]
            if let matcher = spec.matcher { group["matcher"] = matcher }
            groups.append(group)
            hooks[spec.event] = groups
        }

        root["hooks"] = hooks
        try writeJSON(root, to: paths.museSettings)
    }

    func removeMuseHooks() {
        let fm = FileManager.default
        guard var root = readJSON(paths.museSettings),
              var hooks = root["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups = groups.compactMap { group in
                var group = group
                var entries = group["hooks"] as? [[String: Any]] ?? []
                entries.removeAll { isPrismaHook($0) }
                guard !entries.isEmpty else { return nil }
                group["hooks"] = entries
                return group
            }
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        // A file left holding only the required version carries nothing else.
        if root.keys.allSatisfy({ $0 == "schema_version" }) {
            try? fm.removeItem(at: paths.museSettings)
        } else {
            try? writeJSON(root, to: paths.museSettings)
        }
    }

    // MARK: Antigravity

    /// Events that take plain handlers, and the tool events that take groups.
    func antigravityStopCommand() -> String {
        "bash \"\(paths.support.path)/on_stop.sh\" antigravity Stop"
    }

    func antigravityPreToolCommand() -> String {
        "bash \"\(paths.support.path)/on_stop.sh\" antigravity PreToolUse"
    }

    func antigravityHooksInstalled() -> Bool {
        guard let root = readJSON(paths.antigravityHooks),
              let entry = root["prisma"] as? [String: Any],
              let stop = entry["Stop"] as? [[String: Any]],
              let gate = entry["PreToolUse"] as? [[String: Any]],
              let session = entry["SessionStart"] as? [[String: Any]],
              let invocation = entry["PreInvocation"] as? [[String: Any]] else { return false }
        let stopOK = stop.contains { ($0["command"] as? String) == antigravityStopCommand() }
        let gateOK = gate.contains { group in
            let handlers = group["hooks"] as? [[String: Any]] ?? []
            return handlers.contains { ($0["command"] as? String) == antigravityPreToolCommand() }
        }
        let sessionOK = session.contains { ($0["command"] as? String) == "bash \"\(paths.support.path)/on_turn.sh\" antigravity SessionStart" }
        let invocationOK = invocation.contains { ($0["command"] as? String) == "bash \"\(paths.support.path)/on_turn.sh\" antigravity PreInvocation" }
        return stopOK && gateOK && sessionOK && invocationOK
    }

    func writeAntigravityHooks() throws {
        var root = readJSON(paths.antigravityHooks) ?? [:]
        try backup(paths.antigravityHooks)

        func handler(_ command: String, timeout: Int) -> [String: Any] {
            ["type": "command", "command": command, "timeout": timeout]
        }

        root["prisma"] = [
            "SessionStart": [
                handler("bash \"\(paths.support.path)/on_turn.sh\" antigravity SessionStart", timeout: 10)
            ],
            "PreInvocation": [
                handler("bash \"\(paths.support.path)/on_turn.sh\" antigravity PreInvocation", timeout: 10)
            ],
            "Stop": [
                handler(antigravityStopCommand(), timeout: 15)
            ],
            "PreToolUse": [[
                "matcher": "ask_question|ask_permission",
                "hooks": [handler(antigravityPreToolCommand(), timeout: 10)]
            ]]
        ]
        try writeJSON(root, to: paths.antigravityHooks)
    }

    func removeAntigravityHooks() {
        let fm = FileManager.default
        guard var root = readJSON(paths.antigravityHooks) else { return }
        root.removeValue(forKey: "prisma")
        if root.isEmpty {
            try? fm.removeItem(at: paths.antigravityHooks)
        } else {
            try? writeJSON(root, to: paths.antigravityHooks)
        }
    }

    /// One backup per file, so a repeated connect does not overwrite the
    /// original with an already-connected copy.
    private func backup(_ file: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return }
        let copy = file.appendingPathExtension("prisma-backup")
        guard !fm.fileExists(atPath: copy.path) else { return }
        try fm.copyItem(at: file, to: copy)
    }

    // MARK: Files

    private func stageResources() throws {
        let fm = FileManager.default
        let source = try resourceRoot()
        guard canonical(source) != canonical(paths.dist) else { return }

        try? fm.removeItem(at: paths.dist)
        try fm.createDirectory(at: paths.dist, withIntermediateDirectories: true)
        for name in ["plugin", ".agents", ".claude-plugin"] {
            let from = source.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path) else {
                throw CommandError.failed("Prisma", "Falta \(name) en los archivos de integración.")
            }
            try fm.copyItem(at: from, to: paths.dist.appendingPathComponent(name))
        }
        removeDSStore(in: paths.dist)
    }

    private func installScripts() throws {
        let fm = FileManager.default
        let scripts = paths.dist.appendingPathComponent("plugin/scripts")
        try fm.createDirectory(
            at: paths.support.appendingPathComponent("scripts", isDirectory: true),
            withIntermediateDirectories: true
        )
        for name in ["on_stop.sh", "on_turn.sh"] {
            let source = scripts.appendingPathComponent(name)
            let destinations = [
                paths.support.appendingPathComponent(name),
                paths.support.appendingPathComponent("scripts/\(name)")
            ]
            for destination in destinations {
                try? fm.removeItem(at: destination)
                try fm.copyItem(at: source, to: destination)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            }
        }
    }

    private func appendAgentsBlock(to file: URL, replaceShortFile: Bool) throws {
        let fm = FileManager.default
        let body = try String(
            contentsOf: paths.dist.appendingPathComponent("plugin/AGENTS.md"),
            encoding: .utf8
        )
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)

        var existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        if existing.isEmpty {
            try (body + "\n").write(to: file, atomically: true, encoding: .utf8)
            return
        }
        if !existing.contains("<ForPrisma>") {
            if !existing.hasSuffix("\n") { existing += "\n" }
            existing += "\n" + body + "\n"
        } else if replaceShortFile && existing.components(separatedBy: "\n").count <= 20 {
            existing = body + "\n"
        }
        try existing.write(to: file, atomically: true, encoding: .utf8)
    }

    private func removeAgentsBlock(from file: URL) {
        guard let contents = try? String(contentsOf: file, encoding: .utf8),
              let start = contents.range(of: "## Voice output for Prisma") else { return }

        var end = contents.endIndex
        if let next = contents.range(of: "\n## ", range: start.upperBound..<contents.endIndex) {
            end = next.lowerBound
        }
        var updated = contents
        updated.removeSubrange(start.lowerBound..<end)
        updated = updated.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else {
            try? (updated + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func removeDSStore(in directory: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent == ".DS_Store" {
            try? fm.removeItem(at: item)
        }
        for item in items {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue {
                removeDSStore(in: item)
            }
        }
    }

    private func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    private func canonical(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

// MARK: - Codex hook trust

enum CodexHookTrust {
    /// Codex refuses to run hooks that it has not marked as trusted. The only
    /// supported way to trust them is its own app-server protocol: list the
    /// hooks, then write their current hashes into `hooks.state`.
    ///
    /// Each request goes in its own short-lived session, with the messages
    /// written in one batch: Codex restarts its app server after answering
    /// `hooks/list`, so a request sent after reading that answer is refused.
    static func apply(hooksFile: URL, cwd: URL, timeout: TimeInterval = 20) -> Bool {
        signal(SIGPIPE, SIG_IGN)

        let initialize: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": ["clientInfo": ["name": "prisma-app", "version": "1.0.1"]]
        ]
        let initialized: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:]
        ]
        let list: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "hooks/list",
            "params": ["cwds": [cwd.path]]
        ]

        guard let listResponse = session(
            messages: [initialize, initialized, list],
            waitingFor: 2,
            timeout: min(timeout, 12)
        ) else { return false }

        let target = hooksFile.resolvingSymlinksInPath().standardizedFileURL.path
        var updates: [String: Any] = [:]
        for entry in hookEntries(in: listResponse) {
            let source = (entry["sourcePath"] as? String).map {
                URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
            }
            guard source == target,
                  entry["statusMessage"] as? String == "Prisma",
                  let key = entry["key"] as? String,
                  let hash = entry["currentHash"] as? String else { continue }
            updates[key] = ["trusted_hash": hash]
        }
        guard !updates.isEmpty else { return false }

        let write: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 3,
            "method": "config/batchWrite",
            "params": [
                "edits": [[
                    "keyPath": "hooks.state",
                    "value": updates,
                    "mergeStrategy": "upsert"
                ]],
                "reloadUserConfig": true
            ]
        ]
        guard let writeResponse = session(
            messages: [initialize, initialized, write],
            waitingFor: 3,
            timeout: timeout
        ) else { return false }

        return (writeResponse["result"] as? [String: Any])?["status"] as? String == "ok"
    }

    private static func hookEntries(in response: [String: Any]) -> [[String: Any]] {
        guard let result = response["result"] as? [String: Any],
              let data = result["data"] as? [[String: Any]] else { return [] }
        return data.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    }

    /// Sends the whole sequence at once and returns the response with `waitingFor`.
    private static func session(
        messages: [[String: Any]],
        waitingFor id: Int,
        timeout: TimeInterval
    ) -> [String: Any]? {
        let lines = messages.compactMap { message -> String? in
            guard let data = try? JSONSerialization.data(withJSONObject: message) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        guard lines.count == messages.count else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec codex app-server"]
        process.environment = ProcessInfo.processInfo.environment

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        var finished = false
        let watchdog = DispatchWorkItem {
            if !finished, process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer {
            finished = true
            watchdog.cancel()
            if process.isRunning { process.terminate() }
            try? stdin.fileHandleForWriting.close()
        }

        let payload = lines.joined(separator: "\n") + "\n"
        try? stdin.fileHandleForWriting.write(contentsOf: Data(payload.utf8))

        var buffer = Data()
        let reader = stdout.fileHandleForReading
        while true {
            if let index = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<index]
                buffer.removeSubrange(buffer.startIndex...index)
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                if object["id"] as? Int == id { return object }
                continue
            }
            guard let chunk = try? reader.read(upToCount: 65536), !chunk.isEmpty else { return nil }
            buffer.append(chunk)
        }
    }
}


// MARK: - Observable connector

final class AgentConnector: ObservableObject {
    @Published private(set) var connections: [AgentConnection] = AgentKind.allCases.map {
        AgentConnection(kind: $0, state: .disconnected, detail: "Comprobando…")
    }
    @Published private(set) var working: AgentKind?
    @Published private(set) var jqAvailable = true
    @Published private(set) var lastWarnings: [String] = []

    private let queue = DispatchQueue(label: "com.newton.prisma.agents", qos: .userInitiated)
    private lazy var installer = AgentInstaller(paths: .live())

    func refresh() {
        queue.async {
            let jq = Shell.exists("jq")
            let cli: [AgentKind: Bool] = [
                .codex: Shell.exists("codex"),
                .claudeCode: Shell.exists("claude"),
                .openCode: Shell.exists("opencode"),
                .muse: Shell.exists("muse"),
                .antigravity: Shell.exists("agy")
            ]
            let statuses = AgentKind.allCases.map { kind in
                self.installer.status(for: kind, cliAvailable: cli[kind] ?? false)
            }
            DispatchQueue.main.async {
                self.jqAvailable = jq
                self.connections = statuses
            }
        }
    }

    func connect(_ kind: AgentKind) {
        guard working == nil else { return }
        working = kind
        lastWarnings = []
        setState(kind, .working, "Conectando…")

        queue.async {
            do {
                let warnings = try self.installer.install(kind)
                let status = self.installer.status(for: kind, cliAvailable: Shell.exists(kind.executable))
                DispatchQueue.main.async {
                    self.lastWarnings = warnings
                    self.connections = self.connections.map { $0.kind == kind ? status : $0 }
                    self.working = nil
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    self.lastWarnings = [message]
                    self.connections = self.connections.map { current in
                        guard current.kind == kind else { return current }
                        return AgentConnection(kind: kind, state: .failed("No se pudo conectar"), detail: message)
                    }
                    self.working = nil
                }
            }
        }
    }

    func disconnect(_ kind: AgentKind) {
        guard working == nil else { return }
        working = kind
        lastWarnings = []
        setState(kind, .working, "Desconectando…")

        queue.async {
            try? self.installer.remove(kind)
            let status = self.installer.status(for: kind, cliAvailable: Shell.exists(kind.executable))
            DispatchQueue.main.async {
                self.connections = self.connections.map { $0.kind == kind ? status : $0 }
                self.working = nil
            }
        }
    }

    private func setState(_ kind: AgentKind, _ state: ConnectionState, _ detail: String) {
        connections = connections.map { current in
            guard current.kind == kind else { return current }
            return AgentConnection(kind: kind, state: state, detail: detail)
        }
    }
}
