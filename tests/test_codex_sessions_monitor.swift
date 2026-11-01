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
        print("Resumed Codex session detection passed")
    }
}
