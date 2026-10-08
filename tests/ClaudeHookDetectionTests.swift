import Foundation

@main
enum ClaudeHookDetectionTests {
    static func settings(_ json: String) -> [String: Any] {
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8))
        return (object as? [String: Any]) ?? [:]
    }

    static func main() {
        // Installed: the hook Klayer Island writes, GitHub build
        precondition(klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[{"hooks":[
          {"type":"command","command":"$HOME/.claude/klayer/nb-hook"}]}]}}
        """)))

        // Installed: App Store build names NotchBuddy
        precondition(klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[{"hooks":[
          {"type":"command","command":"/Applications/NotchBuddy.app/.../nb-hook"}]}]}}
        """)))

        // Installed: our hook sits alongside somebody else's
        precondition(klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[
          {"hooks":[{"type":"command","command":"/usr/local/bin/other-tool"}]},
          {"hooks":[{"type":"command","command":"$HOME/.claude/klayer/nb-hook"}]}]}}
        """)))

        // Not installed: other tools only — the case that showed "Key not configured"
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[{"hooks":[
          {"type":"command","command":"$HOME/.vibe-island/bin/vibe-island-bridge"},
          {"type":"command","command":"python3 /Users/me/.claude/skills/harness/hook.py"}]}]}}
        """)))

        // Not installed: hooks for other events do not count
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":{"PreToolUse":[{"hooks":[
          {"type":"command","command":"$HOME/.claude/klayer/nb-hook"}]}]}}
        """)))

        // Malformed or empty settings never crash, and never read as installed
        precondition(!klayerHooksPresent(inSettings: settings("{}")))
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[]}}
        """)))
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":[{"hooks":[{"type":"command"}]}]}}
        """)))
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":{"SessionStart":"not-an-array"}}
        """)))
        precondition(!klayerHooksPresent(inSettings: settings("""
        {"hooks":"not-an-object"}
        """)))

        print("Claude hook detection: 10 cases passed")
    }
}
