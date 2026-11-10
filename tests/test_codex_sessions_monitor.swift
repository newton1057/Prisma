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

        print("Resumed Codex session detection passed")
    }
}
