import Foundation

/// Finds open Muse Code windows, so each one waits with its orb right away,
/// including windows opened before Prisma started. Their hooks report the same
/// process, so the first session event takes the orb over. No conversation
/// contents are inspected.
enum MuseWindows {
    /// Subcommands that do not open a conversation.
    static let otherCommands: Set<String> = [
        "exec", "serve", "export", "trace", "model-profile", "skills", "voice", "plugins",
        "sandbox", "schema", "session-message", "mcp", "auth", "login", "logout", "init", "config",
    ]

    /// Open windows in `ps -axo pid=,args=` output, with the session they
    /// resume when its identifier is a UUID. The launcher execs into a
    /// versioned binary (`muse-bin-<version>`), so either name is a window.
    static func windows(in processList: String) -> [Int32: String?] {
        var windows: [Int32: String?] = [:]
        for line in processList.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, let pid = Int32(fields[0]) else { continue }
            let name = URL(fileURLWithPath: fields[1]).lastPathComponent
            guard name == "muse" || name.hasPrefix("muse-bin-") else { continue }
            let arguments = Array(fields.dropFirst(2))
            // One-shot runs (`muse exec`) still get an orb from their hooks.
            guard opensWindow(arguments) else { continue }
            windows[pid] = resumedSession(in: arguments)
        }
        return windows
    }

    /// The first bare word is the subcommand; a prompt after the options is
    /// not read. Anything that is not a known subcommand opens the TUI.
    static func opensWindow(_ arguments: [String]) -> Bool {
        for argument in arguments where !argument.hasPrefix("-") {
            return !otherCommands.contains(argument)
        }
        return true
    }

    static func resumedSession(in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() where argument == "resume" {
            guard index + 1 < arguments.count else { continue }
            if let id = UUID(uuidString: arguments[index + 1]) {
                return id.uuidString.lowercased()
            }
        }
        return nil
    }
}
