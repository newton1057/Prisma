import Darwin
import Foundation

@main
struct TestCodexSessionsMonitor {
    static func main() {
        let one = "01a19592-8739-7d53-89e1-7398f62ddfd2"
        let two = "01a14641-9857-7a30-adca-b4263be8303b"
        let processes = """
          100 /Users/me/.local/bin/codex resume \(one)
          101 codex resume \(one)
          102 codex --no-alt-screen resume \(two.uppercased())
          103 codex app-server --listen unix://
          104 codex exec resume \(one)
          105 codex resume not-a-session
          106 /bin/sh -c codex resume \(one)
        """
        let actual = CodexSessionsMonitor.resumedSessions(in: processes)
        precondition(actual == [one, two], "Unexpected sessions: \(actual)")
        let pids = CodexSessionsMonitor.resumedSessionPIDs(in: processes)
        precondition(pids == [one: 100, two: 102], "Unexpected session PIDs: \(pids)")

        let fm = FileManager.default
        let tempCodex = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-locks-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempCodex) }

        precondition(CodexSessionsMonitor.isSessionLocked(one, codexHome: tempCodex) == nil,
                     "Without thread-writer-locks directory, lock check must return nil")

        let locksDir = tempCodex.appendingPathComponent("thread-writer-locks", isDirectory: true)
        try! fm.createDirectory(at: locksDir, withIntermediateDirectories: true)
        precondition(CodexSessionsMonitor.isSessionLocked("not-a-uuid", codexHome: tempCodex) == nil,
                     "Non-UUID session ids must return nil")
        precondition(CodexSessionsMonitor.isSessionLocked(one, codexHome: tempCodex) == false,
                     "Missing lock file must report unlocked")

        let lockFile = locksDir.appendingPathComponent("\(one).lock")
        fm.createFile(atPath: lockFile.path, contents: Data())
        precondition(CodexSessionsMonitor.isSessionLocked(one, codexHome: tempCodex) == false,
                     "Unlocked file must report unlocked")

        let fd = open(lockFile.path, O_RDWR)
        precondition(fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0, "Failed to acquire test lock")
        precondition(CodexSessionsMonitor.isSessionLocked(one, codexHome: tempCodex) == true,
                     "Exclusively locked file must report locked")
        _ = flock(fd, LOCK_UN)
        close(fd)
        precondition(CodexSessionsMonitor.isSessionLocked(one, codexHome: tempCodex) == false,
                     "Released lock must report unlocked")

        testAgentProcessFilter()
        testAgentProcessListMatchesPS()
        print("Resumed Codex session detection passed")
    }

    /// The executable name is read like the detectors read it: the last path
    /// component of the first word.
    static func testAgentProcessFilter() {
        let cases: [(String, Substring, Bool)] = [
            ("/Users/me/.local/bin/codex resume x", "codex", true),
            ("codex --no-alt-screen resume x", "codex", true),
            ("  claude --resume x", "claude", true),
            ("/Users/me/.opencode/bin/opencode serve --service", "opencode", true),
            ("/Users/me/.local/bin/muse-bin-1.4.14-R7309.1", "muse-bin-1.4.14-R7309.1", true),
            ("muse resume --last", "muse", true),
            ("agy --conversation x", "agy", true),
            ("/bin/sh -c codex resume x", "sh", false),
            ("/usr/bin/node /Users/me/.npm/bin/opencode", "node", false),
            ("script -q /dev/null opencode", "script", false),
            ("codex-helper", "codex-helper", false),
            ("opencode-helper", "opencode-helper", false),
            ("/Applications/Codex.app/Contents/MacOS/Codex", "Codex", false),
            ("codex/", "codex", true),
        ]
        for (line, name, agent) in cases {
            let actual = CodexSessionsMonitor.commandName(of: line[...])
            precondition(actual == name, "command name of \(line): \(actual)")
            precondition(CodexSessionsMonitor.isAgentExecutable(actual) == agent, "agent filter for \(line)")
        }
    }

    /// The in-process process table keeps the same agent lines `ps` shows.
    /// Processes can start or exit between the two reads, so retry a few times.
    static func testAgentProcessListMatchesPS() {
        func normalized(_ text: String) -> Set<String> {
            Set(text.split(separator: "\n").map { line in
                line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }.filter { line in
                guard let space = line.firstIndex(of: " ") else { return false }
                return CodexSessionsMonitor.isAgentExecutable(
                    CodexSessionsMonitor.commandName(of: line[line.index(after: space)...]))
            })
        }
        func ps() -> String {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["-axo", "pid=,args="]
            let output = Pipe()
            task.standardOutput = output
            try! task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        var mine: Set<String> = []
        var theirs: Set<String> = []
        for _ in 0..<5 {
            mine = normalized(CodexSessionsMonitor.agentProcessList() ?? "")
            theirs = normalized(ps())
            if mine == theirs { break }
            usleep(200_000)
        }
        precondition(mine == theirs, "agent processes differ from ps: only ps \(theirs.subtracting(mine)), only Prisma \(mine.subtracting(theirs))")
        print("Agent process table matches ps (\(mine.count) agent processes)")
    }
}
