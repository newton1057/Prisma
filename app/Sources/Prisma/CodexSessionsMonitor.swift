import Darwin
import Foundation

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
        var seen = Set<String>()
        var sessions: [String] = []
        for line in processList.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 4, Int(fields[0]) != nil,
                  URL(fileURLWithPath: fields[1]).lastPathComponent == "codex",
                  let resume = fields.firstIndex(of: "resume"), resume + 1 < fields.count,
                  fields[2..<resume].allSatisfy({ $0.hasPrefix("-") }),
                  let id = UUID(uuidString: fields[resume + 1])?.uuidString.lowercased(),
                  seen.insert(id).inserted else { continue }
            sessions.append(id)
        }
        return sessions
    }

    static func resumedSessionPIDs(in processList: String) -> [String: Int32] {
        var result: [String: Int32] = [:]
        for line in processList.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 4, let pid = Int32(fields[0]),
                  URL(fileURLWithPath: fields[1]).lastPathComponent == "codex",
                  let resume = fields.firstIndex(of: "resume"), resume + 1 < fields.count,
                  fields[2..<resume].allSatisfy({ $0.hasPrefix("-") }),
                  let id = UUID(uuidString: fields[resume + 1])?.uuidString.lowercased(),
                  result[id] == nil else { continue }
            result[id] = pid
        }
        return result
    }

    static func snapshot() -> [String]? {
        processList().map(resumedSessions(in:))
    }

    /// `ps -axo pid=,args=` output, shared by the Codex and OpenCode monitors.
    static func processList() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,args="]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
