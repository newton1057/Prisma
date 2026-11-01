import Foundation

/// Which processes are Claude Code and OpenCode conversation windows.
@main
struct TestAgentWindows {
    static func main() {
        testOpenCode()
        testClaudeCode()
        print("Claude Code and OpenCode window detection passed")
    }

    static func testOpenCode() {
        let processes = """
          100 /Users/me/.opencode/bin/opencode
          101 opencode -c
          102 /Users/me/.opencode/bin/opencode serve --service
          103 opencode run arregla la web y serve los archivos
          104 opencode --model gpt-5 web
          105 opencode auth login
          106 /usr/bin/node /Users/me/.npm/bin/opencode
          107 opencode-helper
          108 opencode /Users/me/project
          109 /Users/me/.npm/lib/node_modules/opencode-darwin-arm64/bin/opencode -m gpt-5
          110 script -q /dev/null /Users/me/.opencode/bin/opencode
        """
        // The npm wrapper is not the window: the binary it starts (109) is.
        let windows = OpenCodeWindows.candidates(in: processes)
        precondition(windows == [100, 101, 103, 108, 109], "Unexpected OpenCode windows: \(windows)")

        precondition(OpenCodeWindows.window(in: "/Users/me/project", shows: "/Users/me/project/"))
        precondition(OpenCodeWindows.window(in: "/Users/me/project/app", shows: "/Users/me/project"))
        precondition(!OpenCodeWindows.window(in: "/Users/me/project", shows: "/Users/me/project-two"))
        precondition(!OpenCodeWindows.window(in: "/Users/me", shows: "/Users/me/project"))
        precondition(!OpenCodeWindows.window(in: nil, shows: "/Users/me/project"))
    }

    static func testClaudeCode() {
        let resumed = "0261abd8-e06a-45bc-8839-d8897b820b6f"
        let processes = """
          200 claude
          201 /Users/me/.local/bin/claude --resume \(resumed.uppercased())
          202 claude -p resume este proyecto
          203 claude mcp serve
          204 claude --model opus -c
          205 /bin/zsh -c claude
          206 claude --print hola
          207 claude --session-id=\(resumed)
          208 claude-helper
        """
        let windows = ClaudeCodeWindows.windows(in: processes)
        precondition(Set(windows.keys) == [200, 201, 204, 207], "Unexpected Claude Code windows: \(windows.keys.sorted())")
        precondition(windows[200]! == nil && windows[204]! == nil)
        precondition(windows[201]! == resumed && windows[207]! == resumed, "Resumed sessions not recognised")
    }
}
