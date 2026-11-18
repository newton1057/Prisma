import Darwin
import Foundation

/// Native argv is retained through detection instead of joining and parsing
/// the same command line six times. The text adapter is for fixtures and ps QA.
struct AgentProcess: Equatable {
    let pid: Int32
    let executable: String
    var command: String? = nil
    let arguments: [String]

    static func parse(_ processList: String) -> [AgentProcess] {
        processList.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, let pid = Int32(fields[0]) else { return nil }
            return AgentProcess(pid: pid, executable: URL(fileURLWithPath: String(fields[1])).lastPathComponent,
                                arguments: fields.dropFirst(2).map(String.init))
        }
    }
}

/// Identifies interactive `codex resume` clients, including sessions that were
/// already open when Prisma started. No conversation contents are inspected.
enum CodexSessionsMonitor {
    private static func defaultCodexHome() -> URL {
        let custom = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom, !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    /// Returns whether Codex currently holds an exclusive writer lock on
    /// `<codexHome>/thread-writer-locks/<id>.lock`, or `nil` when `id` is not
    /// a session UUID or the lock directory does not exist.
    static func isSessionLocked(_ id: String, codexHome: URL? = nil) -> Bool? {
        guard let uuid = UUID(uuidString: id)?.uuidString.lowercased() else { return nil }
        let home = codexHome ?? defaultCodexHome()
        let locksDir = home.appendingPathComponent("thread-writer-locks", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: locksDir.path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }
        let lockFile = locksDir.appendingPathComponent("\(uuid).lock")
        let fd = open(lockFile.path, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_SH | LOCK_NB) == 0 {
            _ = flock(fd, LOCK_UN)
            return false
        }
        return errno == EWOULDBLOCK || errno == EAGAIN
    }
    static func resumedSessions(in processList: String) -> [String] {
        resumedClients(in: AgentProcess.parse(processList)).sessions
    }

    static func resumedSessionPIDs(in processList: String) -> [String: Int32] {
        resumedClients(in: AgentProcess.parse(processList)).pids
    }

    static func resumedClients(in processes: [AgentProcess]) -> (sessions: [String], pids: [String: Int32]) {
        var sessions: [String] = []
        var pids: [String: Int32] = [:]
        for process in processes where process.executable == "codex" {
            let args = process.arguments
            guard let resume = args.firstIndex(of: "resume"), resume + 1 < args.count,
                  args[..<resume].allSatisfy({ $0.hasPrefix("-") }),
                  let id = UUID(uuidString: args[resume + 1])?.uuidString.lowercased(),
                  pids[id] == nil else { continue }
            pids[id] = process.pid
            sessions.append(id)
        }
        return (sessions, pids)
    }

    /// Command lines of the agent processes, one `pid args…` line each like
    /// `ps -axo pid=,args=`, shared by the Codex, Claude Code, OpenCode, Muse
    /// Code and Antigravity detectors. They are read in-process with
    /// `KERN_PROCARGS2` instead of starting `ps` every two seconds, and only
    /// the processes whose executable is an agent are kept, so each detector
    /// parses a handful of lines instead of the whole process table.
    static func agentProcessList() -> String? {
        agentProcesses()?.map { "\($0.pid) \($0.command ?? $0.executable) \($0.arguments.joined(separator: " "))".replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "\n")
    }

    static func agentProcesses() -> [AgentProcess]? {
        let pids = allProcessIDs()
        guard !pids.isEmpty else { return nil }
        var buffer = [UInt8](repeating: 0, count: argumentsBufferSize)
        return pids.filter { $0 > 0 }.compactMap { agentProcess(of: $0, buffer: &buffer) }
    }

    /// Executable names the detectors look for.
    static func isAgentExecutable(_ name: Substring) -> Bool {
        name == "codex" || name == "claude" || name == "opencode" || name == "agy"
            || name == "muse" || name.hasPrefix("muse-bin-")
    }

    /// Last path component of the first word of a command line, the same
    /// word the detectors take as the executable.
    static func commandName(of commandLine: Substring) -> Substring {
        let start = commandLine.drop(while: \.isWhitespace)
        var word = start.prefix(while: { !$0.isWhitespace })
        while word.count > 1, word.hasSuffix("/") { word = word.dropLast() }
        guard let slash = word.lastIndex(of: "/"), word.count > 1 else { return word }
        return word[word.index(after: slash)...]
    }

    private static let argumentsBufferSize: Int = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0, value > 0 else { return 1 << 20 }
        return Int(value)
    }()

    private static func allProcessIDs() -> [Int32] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<Int32>.size))
        }
        return Array(pids.prefix(Int(max(0, count))))
    }

    /// The arguments of an agent process joined by spaces, as `ps` prints
    /// them, or nil for any other process. `KERN_PROCARGS2` holds the argument
    /// count, the executable path and its padding, then the arguments.
    /// Processes of other users cannot be read and return nil, which never
    /// hides an agent started by this user.
    private static func agentProcess(of pid: Int32, buffer: inout [UInt8]) -> AgentProcess? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = buffer.count
        let status = buffer.withUnsafeMutableBytes { raw in
            sysctl(&mib, 3, raw.baseAddress, &size, nil, 0)
        }
        let header = MemoryLayout<Int32>.size
        guard status == 0, size > header else { return nil }
        let count = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        guard count > 0 else { return nil }
        var index = header
        while index < size && buffer[index] != 0 { index += 1 }
        while index < size && buffer[index] == 0 { index += 1 }
        // Most processes are not agents. When the first argument is plain
        // ASCII without spaces it is the executable word itself, so its name
        // decides without building any string.
        var end = index
        var plain = end < size && buffer[end] != 0
        while end < size && buffer[end] != 0 {
            let byte = buffer[end]
            if byte >= 0x80 || byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) { plain = false }
            end += 1
        }
        if plain, !isAgentExecutable(asciiName(buffer[index..<end])) { return nil }
        var arguments: [String] = []
        while arguments.count < count && index < size {
            let start = index
            while index < size && buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
            // Most processes are not agents: decide from the first argument
            // before reading the rest, unless it is blank.
            if arguments.count == 1, arguments[0].contains(where: { !$0.isWhitespace }),
               !isAgentExecutable(commandName(of: arguments[0][...])) {
                return nil
            }
        }
        let line = arguments.joined(separator: " ")
        guard isAgentExecutable(commandName(of: line[...])) else { return nil }
        return AgentProcess(pid: pid, executable: String(commandName(of: line[...])),
                            command: arguments.first, arguments: Array(arguments.dropFirst()))
    }

    /// `commandName` of a word of ASCII bytes without whitespace. Agent names
    /// are short, so longer names are cut short instead of decoded in full.
    private static func asciiName(_ word: ArraySlice<UInt8>) -> Substring {
        var end = word.endIndex
        while end - word.startIndex > 1, word[end - 1] == UInt8(ascii: "/") { end -= 1 }
        var start = end
        while start > word.startIndex, word[start - 1] != UInt8(ascii: "/") { start -= 1 }
        if start == end { start = word.startIndex }
        let name = word[start..<min(end, start + 64)]
        return Substring(String(decoding: name, as: UTF8.self))
    }
}
