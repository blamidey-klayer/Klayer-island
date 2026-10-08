import Foundation

@main
enum ClaudeHookDetectionTests {
    static func settings(_ json: String) -> [String: Any] {
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8))
        return (object as? [String: Any]) ?? [:]
    }

    /// Klayer Island as installed for the user "me".
    static let ours = KlayerHookCommand(
        scriptPath: "/Users/me/Library/Application Support/NotchBuddy/nb-hook",
        home: "/Users/me")

    static func main() {
        // MARK: Which commands are Klayer Island's own

        // The command the app writes today: its script, quoted (the path has a space)
        precondition(ours.written == #""/Users/me/Library/Application Support/NotchBuddy/nb-hook""#)
        precondition(ours.isOurs(ours.written))
        precondition(ours.isOurs(ours.written + " --ask"))
        precondition(ours.isOurs("  " + ours.written + "  --ask  "))
        precondition(ours.isOurs("/bin/sh " + ours.written))
        precondition(ours.isOurs(#"/bin/sh ~/Library/Application\ Support/NotchBuddy/nb-hook --agent claude-desktop"#))
        precondition(ours.isOurs(#"'/Users/me/Library/Application Support/NotchBuddy/nb-hook' --statusline"#))

        // What earlier builds wrote: ~/.claude/klayer/nb-hook, through /bin/sh, in any spelling of home
        for legacy in [#"/bin/sh "/Users/me/.claude/klayer/nb-hook""#,
                       #"/bin/sh "/Users/me/.claude/klayer/nb-hook" --ask"#,
                       "$HOME/.claude/klayer/nb-hook",
                       "${HOME}/.claude/klayer/nb-hook --ask",
                       "~/.claude/klayer/nb-hook",
                       #""$HOME/.claude/klayer/nb-hook""#] {
            precondition(ours.isOurs(legacy), "legacy command not recognised: \(legacy)")
        }

        // Never the user's own commands, even when "klayer" or "NotchBuddy" is in their path
        for theirs in ["$HOME/tools/klayer-lint.sh",
                       "/Users/me/klayer/scripts/notify.sh",
                       "python3 ~/.claude/klayer/check.py",
                       "~/.claude/klayer/nb-hook.py",
                       "~/.claude/klayer/nb-hook2",
                       "/usr/local/bin/NotchBuddy-helper",
                       #""/Users/me/Library/Application Support/NotchBuddy/other-hook""#,
                       "/Users/someone-else/.claude/klayer/nb-hook",
                       #"echo "/Users/me/Library/Application Support/NotchBuddy/nb-hook""#,
                       // Our script chained with the user's own command: the entry is theirs too
                       #""/Users/me/Library/Application Support/NotchBuddy/nb-hook" && say done"#,
                       #""/Users/me/Library/Application Support/NotchBuddy/nb-hook" 2>/dev/null"#,
                       #""/Users/me/Library/Application Support/NotchBuddy/nb-hook";say done"#,
                       // Unquoted with the space: the shell would not even run our script
                       "/Users/me/Library/Application Support/NotchBuddy/nb-hook",
                       #""/Users/me/Library/Application Support/NotchBuddy/nb-hook"#,
                       "", "   ", "/bin/sh"] {
            precondition(!ours.isOurs(theirs), "the user's command was taken for ours: \(theirs)")
        }

        // MARK: Installed or not

        // Installed: the hook Klayer Island writes today, in its support folder
        precondition(klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[{"hooks":[
          {"type":"command","command":"\\"/Users/me/Library/Application Support/NotchBuddy/nb-hook\\""}]}]}}
        """), ours: ours))

        // Installed: the hook an earlier build wrote in ~/.claude/klayer
        precondition(klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[{"hooks":[
          {"type":"command","command":"$HOME/.claude/klayer/nb-hook"}]}]}}
        """), ours: ours))

        // Installed: our hook sits alongside somebody else's
        precondition(klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[
          {"hooks":[{"type":"command","command":"/usr/local/bin/other-tool"}]},
          {"hooks":[{"type":"command","command":"$HOME/.claude/klayer/nb-hook"}]}]}}
        """), ours: ours))

        // Not installed: other tools only, the case that showed "Key not configured"
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[{"hooks":[
          {"type":"command","command":"$HOME/.vibe-island/bin/vibe-island-bridge"},
          {"type":"command","command":"python3 /Users/me/.claude/skills/harness/hook.py"}]}]}}
        """), ours: ours))

        // Not installed: a hook of the user's own whose path says klayer
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[{"hooks":[
          {"type":"command","command":"$HOME/tools/klayer-lint.sh"}]}]}}
        """), ours: ours))

        // Not installed: hooks for other events do not count
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":{"PreToolUse":[{"hooks":[
          {"type":"command","command":"$HOME/.claude/klayer/nb-hook"}]}]}}
        """), ours: ours))

        // Malformed or empty settings never crash, and never read as installed
        precondition(!klayerHooksPresent(inSettings: settings("{}"), ours: ours))
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[]}}
        """), ours: ours))
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[{"hooks":[{"type":"command"}]}]}}
        """), ours: ours))
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":"not-an-array"}}
        """), ours: ours))
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":"not-an-object"}
        """), ours: ours))

        // MARK: Outdated or not

        let current = settings("""
        {"hooks":{
          "PermissionRequest":[{"hooks":[{"type":"command","command":"$HOME/.claude/klayer/nb-hook","timeout":120}]}],
          "PreToolUse":[{"matcher":"AskUserQuestion","hooks":[
            {"type":"command","command":"$HOME/.claude/klayer/nb-hook --ask","timeout":130}]}]}}
        """)
        precondition(!klayerHooksNeedUpdate(inSettings: current, ours: ours))
        // Our permission hook with the old 110 s timeout
        precondition(klayerHooksNeedUpdate(inSettings: settings("""
        {"hooks":{
          "PermissionRequest":[{"hooks":[{"type":"command","command":"$HOME/.claude/klayer/nb-hook","timeout":110}]}],
          "PreToolUse":[{"matcher":"AskUserQuestion","hooks":[
            {"type":"command","command":"$HOME/.claude/klayer/nb-hook --ask","timeout":130}]}]}}
        """), ours: ours))
        // Our hooks without the AskUserQuestion entry
        precondition(klayerHooksNeedUpdate(inSettings: settings("""
        {"hooks":{"PermissionRequest":[{"hooks":[
          {"type":"command","command":"$HOME/.claude/klayer/nb-hook","timeout":120}]}]}}
        """), ours: ours))
        // A user's own hook with "klayer" in its path is none of our business
        precondition(!klayerHooksNeedUpdate(inSettings: settings("""
        {"hooks":{"PermissionRequest":[{"hooks":[
          {"type":"command","command":"$HOME/tools/klayer-guard.sh","timeout":30}]}]}}
        """), ours: ours))
        precondition(!klayerHooksNeedUpdate(inSettings: settings("{}"), ours: ours))

        // MARK: What the app installs

        let groups = ours.installGroups
        let events = groups.map(\.event)
        for event in ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                      "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure",
                      "SubagentStart", "SubagentStop"] {
            precondition(events.contains(event), "no hook installed for \(event)")
        }
        for (_, group) in groups {
            for hook in group["hooks"] as? [[String: Any]] ?? [] {
                precondition(ours.isOurs(hook["command"] as? String ?? ""), "the app installs a command it does not recognise")
            }
        }
        let ask = groups.first { $0.group["matcher"] as? String == "AskUserQuestion" }
        let askHook = (ask?.group["hooks"] as? [[String: Any]])?.first
        precondition(ask?.event == "PreToolUse" && askHook?["command"] as? String == ours.written + " --ask"
                     && askHook?["timeout"] as? Int == 130)
        let permission = groups.first { $0.event == "PermissionRequest" }
        precondition(((permission?.group["hooks"] as? [[String: Any]])?.first?["timeout"] as? Int) == 120)

        // MARK: Agents

        // Agents: only the Claude desktop app gets a pill of its own
        precondition(validateAgent("claude-desktop") == "claude-desktop")

        // An agent Klayer Island used to follow creates no pill any more
        precondition(validateAgent("codex") == nil)
        precondition(isUnrecognisedAgent("codex"))

        // ...and neither does any other name: only the desktop tag is recognised
        for other in ["some-agent", "another-tool", "x", "agent-with-digits-2", "UPPER"] {
            precondition(validateAgent(other) == nil)
            precondition(isUnrecognisedAgent(other))
        }

        // "claude" cannot stand in for the Claude Code pill, nor can a near miss of the desktop tag
        precondition(validateAgent("claude") == nil)
        precondition(isUnrecognisedAgent("claude"))
        precondition(validateAgent("Claude-Desktop") == nil)
        precondition(validateAgent("claude-desktop2") == nil)
        precondition(validateAgent(" claude-desktop") == nil)

        // Claude Code sends no klayer_agent: no pill name, and not an unrecognised agent either
        precondition(validateAgent("") == nil)
        precondition(!isUnrecognisedAgent(""))
        precondition(!isUnrecognisedAgent("claude-desktop"))

        print("Claude hook detection: all checks passed")
    }
}
