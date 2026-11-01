import Foundation

/// Finds open Claude Code windows, so each one waits with its orb right away,
/// including windows opened before Prisma started. Their hooks report the same
/// process, so the first session event takes the orb over. No conversation
/// contents are inspected.
enum ClaudeCodeWindows {
    /// Subcommands that do not open a conversation.
    static let otherCommands: Set<String> = [
        "mcp", "config", "doctor", "update", "upgrade", "install", "uninstall", "plugin", "plugins",
        "setup-token", "migrate-installer", "auth", "login", "logout", "api-key", "daemon", "serve", "server",
    ]

    /// Open windows in `ps -axo pid=,args=` output, with the session they
    /// resume when it is named on the command line.
    static func windows(in processList: String) -> [Int32: String?] {
        var windows: [Int32: String?] = [:]
        for line in processList.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, let pid = Int32(fields[0]),
                  URL(fileURLWithPath: fields[1]).lastPathComponent == "claude" else { continue }
            let arguments = Array(fields.dropFirst(2))
            // One-shot runs (`-p`) still get an orb from their hooks while they run.
            guard !arguments.contains("-p"), !arguments.contains("--print"),
                  arguments.first(where: { !$0.hasPrefix("-") }).map({ !otherCommands.contains($0) }) ?? true
            else { continue }
            windows[pid] = resumedSession(in: arguments)
        }
        return windows
    }

    static func resumedSession(in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            var value: String?
            if ["--resume", "-r", "--session-id"].contains(argument), index + 1 < arguments.count {
                value = arguments[index + 1]
            } else if argument.hasPrefix("--resume=") || argument.hasPrefix("--session-id=") {
                value = argument.split(separator: "=", maxSplits: 1).last.map(String.init)
            }
            if let value, let id = UUID(uuidString: value) {
                return id.uuidString.lowercased()
            }
        }
        return nil
    }
}
