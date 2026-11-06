import Foundation

/// Which processes are Claude Code and OpenCode conversation windows.
@main
struct TestAgentWindows {
    static func main() {
        testOpenCode()
        testClaudeCode()
        testMuse()
        testAntigravity()
        print("Claude Code, OpenCode, Muse Code and Antigravity window detection passed")
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

    static func testMuse() {
        let resumed = "01a1aeda-0bfb-7493-8e01-f9aeba250906"
        let processes = """
          300 muse
          301 /Users/me/.local/bin/muse
          302 /Users/me/.local/bin/muse-bin-1.4.14-R7309.1
          303 muse exec "arregla el test"
          304 muse exec --provider meta "hola"
          305 muse resume \(resumed)
          306 muse resume --last
          307 muse skills list
          308 muse serve
          309 muse "haz algo"
          310 muse --model muse-spark-1.3
          311 /bin/zsh -c muse
          312 muse-helper
        """
        let windows = MuseWindows.windows(in: processes)
        precondition(
            Set(windows.keys) == [300, 301, 302, 305, 306, 309, 310],
            "Unexpected Muse Code windows: \(windows.keys.sorted())"
        )
        precondition(windows[300]! == nil && windows[310]! == nil)
        precondition(windows[305]! == resumed, "Resumed Muse sessions not recognised")
        precondition(windows[306]! == nil, "resume --last has no session id to match")
    }

    static func testAntigravity() {
        let resumed = "08261929-b631-4192-9373-26bc0a503b26"
        let processes = """
          400 agy
          401 /Users/me/.local/bin/agy
          402 agy -p "responde hola"
          403 agy --print "hola"
          404 agy update
          405 agy plugin list
          406 agy --conversation \(resumed)
          407 agy --continue
          408 agy -i "haz algo"
          409 agy mcp add foo
          410 agy agents
          411 /bin/zsh -c agy
          412 agy --model "Gemini 3" "haz algo"
        """
        let windows = AntigravityWindows.windows(in: processes)
        precondition(
            Set(windows.keys) == [400, 401, 406, 407, 408, 412],
            "Unexpected Antigravity windows: \(windows.keys.sorted())"
        )
        precondition(windows[400]! == nil && windows[408]! == nil)
        precondition(windows[406]! == resumed, "Resumed Antigravity conversations not recognised")
    }
}
