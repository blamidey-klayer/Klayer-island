import Foundation

/// Klayer Island's own hook commands in ~/.claude/settings.json, and nothing else.
///
/// The file belongs to the user: a hook of theirs may live under a path that says "klayer" or
/// "NotchBuddy", so install, uninstall and detection never match on a word. A command is ours
/// when it runs one of the two scripts Klayer Island ever wrote: today's `nb-hook` in its support
/// folder (`HookServer.hookScriptPath`), or the `~/.claude/klayer/nb-hook` of earlier builds.
/// It may go through `/bin/sh`, spell the home folder `~`, `$HOME` or `${HOME}`, quote the path,
/// and pass plain arguments (`--ask`, `--agent claude-desktop`); anything else after the script,
/// such as `&&`, a pipe or a redirection, makes the entry the user's.
/// Foundation only, tested by scripts/test-claude-hooks.sh and scripts/test-claude-settings.sh.
struct KlayerHookCommand: Sendable, Equatable {
    /// Where the app writes its script today.
    let scriptPath: String
    /// The user's home folder, for `~` and the script of earlier builds.
    let home: String

    init(scriptPath: String, home: String) {
        self.scriptPath = scriptPath
        self.home = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
    }

    /// The script earlier builds wrote, in ~/.claude/klayer.
    var legacyScriptPath: String { home + "/.claude/klayer/nb-hook" }

    /// The command the app writes: its script between double quotes (the path has a space).
    var written: String { "\"\(scriptPath.replacingOccurrences(of: "\"", with: "\\\""))\"" }

    /// The hook groups Klayer Island installs, one per event, plus the AskUserQuestion hook.
    var installGroups: [(event: String, group: [String: Any])] {
        let events: [(String, Int)] = [
            ("SessionStart", 10), ("SessionEnd", 10),
            ("UserPromptSubmit", 10),
            ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
            ("PermissionRequest", 120),
            ("Notification", 10),
            ("Stop", 10), ("StopFailure", 10),
            ("SubagentStart", 10), ("SubagentStop", 10),
        ]
        var groups = events.map { event, timeout in
            (event: event, group: ["hooks": [["type": "command", "command": written, "timeout": timeout]]] as [String: Any])
        }
        // Dedicated AskUserQuestion PreToolUse hook (Claude Code 2.1.85+, timeout 130 s)
        groups.append((event: "PreToolUse", group: [
            "matcher": "AskUserQuestion",
            "hooks": [["type": "command", "command": "\(written) --ask", "timeout": 130]],
        ]))
        return groups
    }

    /// True when `command` runs Klayer Island's script, as described above.
    func isOurs(_ command: String) -> Bool {
        guard var (word, rest) = Self.firstWord(of: command[...]) else { return false }
        if Self.shells.contains(word) {
            guard let next = Self.firstWord(of: rest) else { return false }
            (word, rest) = next
        }
        guard [scriptPath, legacyScriptPath].contains(expandingHome(word)) else { return false }
        // Only plain arguments may follow: no operator, pipe, redirection or substitution.
        var tail = rest
        while let (argument, after) = Self.firstWord(of: tail) {
            guard !argument.isEmpty, argument.allSatisfy(Self.isPlainArgumentCharacter) else { return false }
            tail = after
        }
        return tail.allSatisfy(\.isWhitespace)
    }

    private static let shells: Set<String> = ["/bin/sh", "sh", "/bin/bash", "bash"]

    private static func isPlainArgumentCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "-" || c == "_" || c == "." || c == "="
    }

    private func expandingHome(_ path: String) -> String {
        for prefix in ["~/", "$HOME/", "${HOME}/"] where path.hasPrefix(prefix) {
            return home + "/" + path.dropFirst(prefix.count)
        }
        return path
    }

    /// The first word of a shell command line with its quotes and backslashes resolved, and what
    /// follows it. Nil when there is no word, or a quote is left open.
    private static func firstWord(of text: Substring) -> (word: String, rest: Substring)? {
        var i = text.startIndex
        while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
        guard i < text.endIndex else { return nil }
        var word = ""
        var quote: Character? = nil
        while i < text.endIndex {
            let c = text[i]
            if let open = quote {
                if c == open {
                    quote = nil
                } else if open == "\"", c == "\\", text.index(after: i) < text.endIndex,
                          "\"\\$`".contains(text[text.index(after: i)]) {
                    i = text.index(after: i)
                    word.append(text[i])
                } else {
                    word.append(c)
                }
            } else if c.isWhitespace {
                break
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "\\", text.index(after: i) < text.endIndex {
                i = text.index(after: i)
                word.append(text[i])
            } else {
                word.append(c)
            }
            i = text.index(after: i)
        }
        guard quote == nil else { return nil }
        return (word, text[i...])
    }
}

/// The command hooks of one event's groups (only the groups with `matcher` when given), each with
/// its hook object. Shapes we do not know are skipped.
private func hookCommands(_ groups: Any?, matcher: String? = nil) -> [(command: String, hook: [String: Any])] {
    guard let groups = groups as? [[String: Any]] else { return [] }
    return groups.flatMap { group -> [(command: String, hook: [String: Any])] in
        if let matcher, group["matcher"] as? String != matcher { return [] }
        return ((group["hooks"] as? [[String: Any]]) ?? []).compactMap { hook in
            (hook["command"] as? String).map { (command: $0, hook: hook) }
        }
    }
}

/// True when a parsed ~/.claude/settings.json routes Claude Code SessionStart events to Klayer Island.
///
/// Kept free of file access so it can be tested on fixtures instead of the real settings file.
func klayerHooksPresent(inSettings settings: [String: Any], ours: KlayerHookCommand) -> Bool {
    guard let hooks = settings["hooks"] as? [String: Any] else { return false }
    return hookCommands(hooks["SessionStart"]).contains { ours.isOurs($0.command) }
}

/// True when Klayer Island's hooks are installed but outdated: a PermissionRequest hook with a
/// timeout under 120 s, or no AskUserQuestion PreToolUse hook (needed since Claude Code 2.1.85).
func klayerHooksNeedUpdate(inSettings settings: [String: Any], ours: KlayerHookCommand) -> Bool {
    guard let hooks = settings["hooks"] as? [String: Any] else { return false }
    let permission = hookCommands(hooks["PermissionRequest"]).filter { ours.isOurs($0.command) }
    guard !permission.isEmpty else { return false }
    if permission.contains(where: { ($0.hook["timeout"] as? Int).map { $0 < 120 } ?? false }) { return true }
    let ask = hookCommands(hooks["PreToolUse"], matcher: "AskUserQuestion").contains { ours.isOurs($0.command) }
    return !ask
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
