import Foundation

/// Checks the agent connections that Ajustes installs: the Codex hooks merge,
/// the AGENTS/CLAUDE instruction block, the OpenCode plugin files, the status
/// detection for all three agents, and that disconnecting only removes Prisma.
@main
struct TestAgentConnections {
    static var failures = 0
    static let fm = FileManager.default

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            print("  ok  \(message)")
        } else {
            failures += 1
            print("  FAIL \(message)")
        }
    }

    static func main() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prisma-agents-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        try? fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = AgentPaths(home: home, support: support, codexHome: codexHome)
        let repo = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        let recorder = Recorder()
        let installer = AgentInstaller(
            paths: paths,
            runCommand: { tool, args in
                recorder.calls.append([tool] + args)
                return CommandResult(status: 0, output: "")
            },
            trustCodexHooks: { _, _ in true },
            resourceRoot: { repo }
        )

        testCodex(installer: installer, paths: paths, recorder: recorder, sourceRoot: repo)
        testClaude(installer: installer, paths: paths, recorder: recorder, repo: repo)
        testOpenCode(installer: installer, paths: paths)
        testMissingCLI(installer: installer)

        if failures > 0 {
            print("\(failures) check(s) failed")
            exit(1)
        }
        print("Agent connections passed")
    }

    // MARK: Codex

    static func testCodex(installer: AgentInstaller, paths: AgentPaths, recorder: Recorder, sourceRoot repo: URL) {
        print("Codex")
        let oldPrisma = ["hooks": [["type": "command", "command": "bash \"x/on_stop.sh\"", "statusMessage": "Prisma"]]]
        let unrelated = ["hooks": [["type": "command", "command": "echo keep-me"]]]
        let seeded: [String: Any] = ["hooks": ["Stop": [unrelated, oldPrisma]]]
        try? fm.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        writeJSON(seeded, to: paths.codexHooks)

        _ = try? installer.install(.codex)
        _ = try? installer.install(.codex)

        let hooks = readJSON(paths.codexHooks)?["hooks"] as? [String: Any] ?? [:]
        let events = Set(hooks.keys)
        let expected: Set<String> = [
            "UserPromptSubmit", "Interrupt", "SessionStart", "SessionEnd",
            "Stop", "PreToolUse", "PermissionRequest"
        ]
        expect(events == expected, "writes the seven Codex hook events")

        let stop = hooks["Stop"] as? [[String: Any]] ?? []
        expect(stop.count == 2, "keeps the unrelated Stop hook and adds exactly one Prisma hook")
        expect(prismaHookCount(stop) == 1, "reinstalling does not duplicate the Prisma hook")

        let turn = "bash \"\(paths.support.path)/on_turn.sh\" codex"
        let stopCommand = "bash \"\(paths.support.path)/on_stop.sh\""
        expect(commandExists(turn, in: hooks["UserPromptSubmit"]), "prompt hook calls on_turn.sh")
        expect(commandExists(stopCommand, in: hooks["PreToolUse"]), "question hook calls on_stop.sh")

        let promptGroups = hooks["PreToolUse"] as? [[String: Any]] ?? []
        let matcher = promptGroups.first?["matcher"] as? String ?? ""
        expect(matcher.contains("AskUserQuestion"), "question hook keeps its matcher")

        expect(fm.isExecutableFile(atPath: paths.support.appendingPathComponent("on_stop.sh").path),
               "copies on_stop.sh into Application Support")
        expect(fm.fileExists(atPath: paths.support.appendingPathComponent("scripts/on_turn.sh").path),
               "copies on_turn.sh into Application Support/scripts")
        expect(fm.fileExists(atPath: paths.dist.appendingPathComponent("plugin/plugin.json").path),
               "stages the plugin for the agent marketplaces")

        let agents = (try? String(contentsOf: paths.codexAgents, encoding: .utf8)) ?? ""
        let sourceBlock = (try? String(contentsOf: repo.appendingPathComponent("plugin/AGENTS.md"), encoding: .utf8)) ?? ""
        expect(agents.contains("<ForPrisma>"), "adds the ForPrisma block to Codex AGENTS.md")
        expect(
            occurrences(of: "<ForPrisma>", in: agents) == occurrences(of: "<ForPrisma>", in: sourceBlock),
            "does not duplicate the AGENTS block"
        )

        var status = installer.status(for: .codex, cliAvailable: true)
        expect(status.state == .incomplete, "reports an incomplete connection until the plugin and trust exist")

        let cache = paths.codexHome.appendingPathComponent("plugins/cache/prisma-local/prisma/1.0.1")
        try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let config = """
        [marketplaces.prisma-local]
        source_type = "local"
        source = "\(paths.dist.path)"

        [plugins."prisma@prisma-local"]
        enabled = true

        [hooks.state]
        [hooks.state."\(paths.codexHooks.path):stop:0:0"]
        trusted_hash = "sha256:abc"
        """
        try? config.write(to: paths.codexConfig, atomically: true, encoding: .utf8)

        status = installer.status(for: .codex, cliAvailable: true)
        expect(status.state == .connected, "reports connected once the plugin is installed and the hooks trusted")

        expect(recorder.calls.contains { $0.prefix(3) == ["codex", "plugin", "add"] },
               "installs the Codex plugin through its CLI")
        expect(recorder.calls.contains { $0.prefix(3) == ["codex", "plugin", "marketplace"] },
               "registers the marketplace that points at the staged plugin")

        try? installer.remove(.codex)
        let afterRemove = readJSON(paths.codexHooks)?["hooks"] as? [String: Any] ?? [:]
        let stopAfter = afterRemove["Stop"] as? [[String: Any]] ?? []
        expect(stopAfter.count == 1, "disconnecting removes only the Prisma hook")
        expect(commandExists("echo keep-me", in: afterRemove["Stop"]), "disconnecting keeps the unrelated hook")
        expect(afterRemove["PreToolUse"] == nil, "disconnecting removes events that only held Prisma hooks")
        let agentsAfter = (try? String(contentsOf: paths.codexAgents, encoding: .utf8)) ?? ""
        expect(!agentsAfter.contains("<ForPrisma>"), "disconnecting removes the ForPrisma block")
    }

    // MARK: Claude Code

    static func testClaude(installer: AgentInstaller, paths: AgentPaths, recorder: Recorder, repo: URL) {
        print("Claude Code")
        try? fm.createDirectory(at: paths.claudeHome.appendingPathComponent("plugins"), withIntermediateDirectories: true)
        writeJSON(
            ["prisma-local": ["installLocation": paths.dist.path]],
            to: paths.claudeKnownMarketplaces
        )
        writeJSON(["version": 2, "plugins": ["prisma@prisma-local": [["scope": "user"]]]], to: paths.claudeInstalledPlugins)
        writeJSON(["enabledPlugins": ["prisma@prisma-local": true]], to: paths.claudeSettings)

        expect(installer.status(for: .claudeCode, cliAvailable: true).state == .connected,
               "detects an enabled plugin that points at the staged marketplace")

        writeJSON(["prisma-local": ["installLocation": repo.path]], to: paths.claudeKnownMarketplaces)
        expect(installer.status(for: .claudeCode, cliAvailable: true).state == .connected,
               "also accepts a marketplace that points at the repository")

        _ = try? installer.install(.claudeCode)
        let commands = recorder.calls.map { $0.joined(separator: " ") }
        expect(commands.contains("claude plugin marketplace add \(paths.dist.path)"),
               "registers the Claude Code marketplace")
        expect(commands.contains("claude plugin install prisma@prisma-local"),
               "installs the Claude Code plugin")

        let agents = (try? String(contentsOf: paths.claudeAgents, encoding: .utf8)) ?? ""
        expect(agents.contains("<ForPrisma>"), "adds the ForPrisma block to CLAUDE.md")

        writeJSON(["enabledPlugins": ["prisma@prisma-local": false]], to: paths.claudeSettings)
        expect(installer.status(for: .claudeCode, cliAvailable: true).state == .incomplete,
               "reports incomplete when the plugin is disabled")
    }

    // MARK: OpenCode

    static func testOpenCode(installer: AgentInstaller, paths: AgentPaths) {
        print("OpenCode")
        expect(installer.status(for: .openCode, cliAvailable: true).state == .disconnected,
               "starts disconnected without plugin files")

        _ = try? installer.install(.openCode)
        expect(fm.fileExists(atPath: paths.openCodePlugin.path), "copies the OpenCode plugin")
        expect(fm.fileExists(atPath: paths.openCodeSkill.path), "copies the OpenCode skill")

        let copied = fm.contents(atPath: paths.openCodePlugin.path)
        let expected = try? Data(contentsOf: paths.dist.appendingPathComponent("plugin/opencode/prisma.ts"))
        expect(copied == expected, "copies the plugin from the staged resources, not from the repository")
        expect(installer.status(for: .openCode, cliAvailable: true).state == .connected,
               "reports connected after copying the files")

        try? installer.remove(.openCode)
        expect(!fm.fileExists(atPath: paths.openCodePlugin.path), "disconnecting removes the OpenCode plugin")
        expect(installer.status(for: .openCode, cliAvailable: true).state == .disconnected,
               "reports disconnected after removal")
    }

    // MARK: Missing CLI

    static func testMissingCLI(installer: AgentInstaller) {
        print("Missing CLI")
        expect(installer.status(for: .codex, cliAvailable: false).state == .agentMissing,
               "marks Codex as missing when its CLI is not installed")
    }

    // MARK: Helpers

    final class Recorder {
        var calls: [[String]] = []
    }

    static func prismaHookCount(_ groups: [[String: Any]]) -> Int {
        groups.reduce(0) { total, group in
            let entries = group["hooks"] as? [[String: Any]] ?? []
            return total + entries.filter { ($0["statusMessage"] as? String) == "Prisma" }.count
        }
    }

    static func commandExists(_ command: String, in value: Any?) -> Bool {
        let groups = value as? [[String: Any]] ?? []
        return groups.contains { group in
            let entries = group["hooks"] as? [[String: Any]] ?? []
            return entries.contains { ($0["command"] as? String) == command }
        }
    }

    static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func writeJSON(_ object: [String: Any], to url: URL) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }
}
