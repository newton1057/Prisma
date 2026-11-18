import Foundation

struct AgentProcessSnapshot {
    let codex: (sessions: [String], pids: [String: Int32])
    let claude: [Int32: String?]
    let openCode: [Int32: String]
    let muse: [Int32: String?]
    let antigravity: [Int32: String?]

    init(_ processes: [AgentProcess]) {
        let groups = Dictionary(grouping: processes) { $0.executable.hasPrefix("muse-bin-") ? "muse" : $0.executable }
        codex = CodexSessionsMonitor.resumedClients(in: groups["codex"] ?? [])
        claude = ClaudeCodeWindows.windows(in: groups["claude"] ?? [])
        openCode = OpenCodeWindows.windows(in: groups["opencode"] ?? [])
        muse = MuseWindows.windows(in: groups["muse"] ?? [])
        antigravity = AntigravityWindows.windows(in: groups["agy"] ?? [])
    }
}
