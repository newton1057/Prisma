import Foundation

/// Finds open Antigravity CLI windows, so each one waits with its orb right
/// away, including windows opened before Prisma started. Their hooks report
/// the same process, so the first session event takes the orb over. No
/// conversation contents are inspected.
enum AntigravityWindows {
    /// Subcommands that do not open a conversation.
    static let otherCommands: Set<String> = [
        "agent", "agents", "changelog", "help", "install", "mcp", "mic-serve", "models",
        "plugin", "plugins", "remote-control", "update",
    ]

    /// Open windows in `ps -axo pid=,args=` output, with the conversation they
    /// resume when `--conversation` names a UUID.
    static func windows(in processList: String) -> [Int32: String?] {
        var windows: [Int32: String?] = [:]
        for line in processList.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, let pid = Int32(fields[0]),
                  URL(fileURLWithPath: fields[1]).lastPathComponent == "agy" else { continue }
            let arguments = Array(fields.dropFirst(2))
            // One-shot runs (`agy -p`) still get an orb from their hooks.
            guard opensWindow(arguments) else { continue }
            windows[pid] = resumedConversation(in: arguments)
        }
        return windows
    }

    static func opensWindow(_ arguments: [String]) -> Bool {
        if arguments.contains("-p") || arguments.contains("--print") || arguments.contains("--prompt") {
            return false
        }
        for argument in arguments where !argument.hasPrefix("-") {
            return !otherCommands.contains(argument)
        }
        return true
    }

    static func resumedConversation(in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            var value: String?
            if argument == "--conversation", index + 1 < arguments.count {
                value = arguments[index + 1]
            } else if argument.hasPrefix("--conversation=") {
                value = argument.split(separator: "=", maxSplits: 1).last.map(String.init)
            }
            if let value, let id = UUID(uuidString: value) {
                return id.uuidString.lowercased()
            }
        }
        return nil
    }
}
