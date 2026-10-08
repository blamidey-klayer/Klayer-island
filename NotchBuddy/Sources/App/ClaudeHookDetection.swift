import Foundation

/// True when a parsed ~/.claude/settings.json routes Claude Code SessionStart events to Klayer Island.
///
/// Kept free of file access so it can be tested on fixtures instead of the real settings file.
/// Both the installed app and earlier builds matched on the command text: a hook written by
/// Klayer Island runs ~/.claude/klayer/nb-hook, and the App Store build names NotchBuddy instead.
func klayerHooksPresent(inSettings settings: [String: Any]) -> Bool {
    guard let hooks = settings["hooks"] as? [String: Any],
          let sessionStart = hooks["SessionStart"] as? [[String: Any]] else { return false }
    return sessionStart.contains { group in
        (group["hooks"] as? [[String: Any]])?.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return command.contains("NotchBuddy") || command.contains("klayer")
        } ?? false
    }
}

/// The `klayer_agent` value of a session that gets its own pill, or nil.
///
/// Klayer Island follows two kinds of session: Claude Code (no `klayer_agent`) and the
/// Claude desktop app, which the relay script tags `claude-desktop` from
/// CLAUDE_CODE_ENTRYPOINT. Any other value comes from a tool Klayer Island no longer follows:
/// no pill is created for it, and its permission requests are answered "ask" so that tool keeps
/// asking in its own terminal. An empty value (Claude Code) also returns nil: use
/// `isUnrecognisedAgent` to tell the two apart.
func validateAgent(_ raw: String) -> String? {
    raw == "claude-desktop" ? raw : nil
}

/// True when a session names an agent Klayer Island does not follow.
func isUnrecognisedAgent(_ raw: String) -> Bool {
    !raw.isEmpty && validateAgent(raw) == nil
}
