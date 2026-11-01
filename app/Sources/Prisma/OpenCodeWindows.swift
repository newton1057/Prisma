import Darwin
import Foundation

/// Finds open OpenCode windows (the terminal app or `opencode run`) and the
/// folder each one works in. OpenCode runs its agent inside one shared
/// background service, so its hooks cannot tell windows apart; Prisma gives
/// each window an orb by watching these processes. No conversation contents
/// are inspected.
enum OpenCodeWindows {
    /// Subcommands that do not open a conversation window.
    static let otherCommands: Set<String> = [
        "serve", "web", "acp", "auth", "login", "logout", "models", "providers", "mcp",
        "upgrade", "uninstall", "reload", "stats", "export", "import", "github", "pr",
        "agent", "debug", "completion", "generate", "plugin", "service", "session", "db",
    ]

    /// Subcommands that do open a conversation (a prompt may follow them).
    static let windowCommands: Set<String> = ["run", "attach"]

    /// Window processes in `ps -axo pid=,args=` output.
    static func candidates(in processList: String) -> [Int32] {
        var pids: [Int32] = []
        for line in processList.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, let pid = Int32(fields[0]),
                  URL(fileURLWithPath: fields[1]).lastPathComponent == "opencode",
                  opensWindow(Array(fields.dropFirst(2))) else { continue }
            pids.append(pid)
        }
        return pids
    }

    /// The first known subcommand decides; option values and a project path
    /// before it do not, and the words of a prompt after `run` are not read.
    private static func opensWindow(_ arguments: [String]) -> Bool {
        for argument in arguments where !argument.hasPrefix("-") {
            if windowCommands.contains(argument) || argument.contains("/") { return true }
            if otherCommands.contains(argument) { return false }
        }
        return true
    }

    /// Open windows and their folders. Helper processes started by a window
    /// are part of that window, not windows of their own.
    static func windows(in processList: String) -> [Int32: String] {
        let pids = candidates(in: processList)
        let all = Set(pids)
        var result: [Int32: String] = [:]
        for pid in pids where !all.contains(parent(of: pid)) {
            if let folder = workingDirectory(of: pid) { result[pid] = folder }
        }
        return result
    }

    /// A session belongs to a window opened in its folder or in one of its subfolders.
    static func window(in windowFolder: String?, shows sessionFolder: String?) -> Bool {
        guard let window = normalized(windowFolder), let session = normalized(sessionFolder) else { return false }
        return window == session || window.hasPrefix(session == "/" ? "/" : session + "/")
    }

    static func normalized(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        var resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        while resolved.count > 1 && resolved.hasSuffix("/") { resolved.removeLast() }
        return resolved
    }

    private static func parent(of pid: Int32) -> Int32 {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return Int32(bitPattern: info.pbi_ppid)
    }

    static func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }
}
