import Foundation

@main
struct TestAgentProcessSnapshot {
    static func main() {
        let id = "01a19592-8739-7d53-89e1-7398f62ddfd2"
        let fixture = """
        100 /bin/codex resume \(id)
        101 codex exec resume \(id)
        102 claude --resume \(id)
        103 claude -p hello
        104 muse-bin-1.0 resume \(id)
        105 agy --conversation=\(id)
        106 opencode serve --service
        107 opencode run hello
        108 /usr/bin/node helper
        """
        let native = AgentProcess.parse(fixture)
        let snapshot = AgentProcessSnapshot(native)
        precondition(snapshot.codex.sessions == CodexSessionsMonitor.resumedSessions(in: fixture))
        precondition(snapshot.codex.pids == CodexSessionsMonitor.resumedSessionPIDs(in: fixture))
        precondition(snapshot.claude == ClaudeCodeWindows.windows(in: fixture))
        precondition(snapshot.muse == MuseWindows.windows(in: fixture))
        precondition(snapshot.antigravity == AntigravityWindows.windows(in: fixture))
        precondition(OpenCodeWindows.candidates(in: native) == [107])
        precondition(snapshot.claude.keys.sorted() == [102])
        precondition(snapshot.muse.keys.sorted() == [104])
        precondition(snapshot.antigravity.keys.sorted() == [105])
        precondition(snapshot.codex.sessions == [id])
        // A prompt argument containing spaces must remain one argv element.
        let prompt = AgentProcess(pid: 109, executable: "claude", arguments: ["-p", "hello --resume \(id)"])
        precondition(ClaudeCodeWindows.windows(in: [prompt]).isEmpty)
        print("Native agent snapshot and detector equivalence passed")
    }
}
