import Foundation

// MARK: - Claude Code, driven as a child process (lot 4)
//
// The island's quick chat and its Gmail draft both go through the user's own Claude Code:
// the island stores no key and no token. This file decides which binary to run, with which
// environment and which arguments. It is Foundation only so that it can be tested on any
// machine; the AppKit side (Process, pipes, timers) lives elsewhere and only drives it.

enum ClaudeCLI {

    /// Fixed model of the chat and of the draft: no picker.
    static let model = "claude-haiku-5-5"

    /// Where the island looks for `claude`, in this order. A GUI app does not inherit the
    /// user's shell PATH, so the usual install folders are tried one by one.
    static func candidatePaths(home: String) -> [String] {
        [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
        ]
    }

    /// The first candidate that is executable, nil when Claude Code is not installed in any
    /// of the usual places (the caller then shows the install message, it never guesses).
    static func locate(home: String, isExecutable: (String) -> Bool) -> String? {
        candidatePaths(home: home).first(where: isExecutable)
    }

    /// Variables that make `claude -p` bill another account or hide the claude.ai connectors:
    /// in print mode an API key always wins over the user's claude.ai login.
    static let scrubbedVariables = [
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "CLAUDE_CODE_OAUTH_TOKEN",
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_FOUNDRY",
        "ANTHROPIC_PROFILE",
    ]

    /// Folders always put on PATH after the binary's own folder.
    private static let standardPathFolders = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    /// The environment of the `claude` process: the app's own environment without the keys
    /// and providers above, tagged `KLAYER_ISLAND_INTERNAL=1` (nb-hook then relays nothing),
    /// and a PATH that starts with the binary's folder (an npm install runs `node` from the
    /// same folder) then the standard folders. Every other variable (HOME, USER, LANG,
    /// TMPDIR…) is kept as is, and no PATH entry appears twice.
    static func environment(from base: [String: String], binary: String) -> [String: String] {
        var env = base
        for key in scrubbedVariables { env.removeValue(forKey: key) }
        env["KLAYER_ISLAND_INTERNAL"] = "1"

        let binaryFolder = (binary as NSString).deletingLastPathComponent
        let existing = (base["PATH"] ?? "").split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        var seen = Set<String>()
        var folders: [String] = []
        // An empty entry is the current directory: never kept, never added.
        for folder in [binaryFolder] + standardPathFolders + existing
        where !folder.isEmpty && seen.insert(folder).inserted {
            folders.append(folder)
        }
        env["PATH"] = folders.joined(separator: ":")
        return env
    }

    /// Inline settings that switch every hook off for the island's own processes.
    private static let noHooksSettings = "{\"disableAllHooks\":true}"

    /// Arguments of the long-lived chat process: messages come in as `stream-json` on stdin,
    /// the answer streams out token by token. No tool of any kind (neither a built-in one nor
    /// an MCP connector of the user's account), nothing saved, no hook.
    static func chatArguments(systemPrompt: String) -> [String] {
        [
            "-p",
            "--model", model,
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--tools", "",
            "--disallowedTools", "mcp__*",
            "--permission-mode", "dontAsk",
            "--no-session-persistence",
            "--settings", noHooksSettings,
            "--system-prompt", systemPrompt,
        ]
    }

    /// The Gmail connector tool that creates a draft. The exact name is checked against the
    /// `tools` of the `system`/`init` event (`ClaudeStream.gmailDraftTool(in:)`).
    static let gmailDraftTool = "mcp__claude_ai_Gmail__create_draft"

    /// Gmail tools that act beyond a draft, denied on top of the allow list.
    static let gmailDeniedTools: [String] = [
        "send_message", "reply", "forward", "update_draft", "delete_draft",
    ].map { "mcp__claude_ai_Gmail__\($0)" }

    /// Arguments of the short draft process: the only tool is the Gmail draft one, nothing
    /// can be sent. `--allowedTools` and `--disallowedTools` take several values, so they come
    /// last, and the request goes through stdin, never as an argument.
    static func draftArguments(systemPrompt: String) -> [String] {
        [
            "-p",
            "--model", model,
            "--output-format", "stream-json",
            "--verbose",
            "--tools", "",
            "--permission-mode", "dontAsk",
            "--setting-sources", "local",
            "--settings", noHooksSettings,
            "--no-session-persistence",
            "--max-turns", "3",
            "--system-prompt", systemPrompt,
            "--allowedTools", gmailDraftTool,
            "--disallowedTools",
        ] + gmailDeniedTools
    }

    /// True when `claude auth status` (JSON) says the user is logged in with a claude.ai
    /// account, the only login that gives access to the claude.ai connectors (Gmail).
    static func authIsClaudeAI(statusJSON: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: statusJSON) as? [String: Any] else { return false }
        if let loggedIn = object["loggedIn"] as? Bool, !loggedIn { return false }
        return object["authMethod"] as? String == "claude.ai"
    }

    /// Where to send someone who has no Claude Code on their Mac.
    static let installURL = URL(string: "https://code.claude.com/docs/en/quickstart")!
}

// MARK: - What a dropped file becomes in the chat

enum ChatAttachmentKind: Equatable {
    case image(mediaType: String)
    case pdf
    case text
    case unsupported

    /// The kind of a file from its extension (any case, with or without the leading dot).
    static func forExtension(_ ext: String) -> ChatAttachmentKind {
        var key = ext.trimmingCharacters(in: .whitespaces).lowercased()
        if key.hasPrefix(".") { key.removeFirst() }
        switch key {
        case "png": return .image(mediaType: "image/png")
        case "jpg", "jpeg": return .image(mediaType: "image/jpeg")
        case "gif": return .image(mediaType: "image/gif")
        case "webp": return .image(mediaType: "image/webp")
        case "pdf": return .pdf
        case "txt", "md", "csv", "json", "swift", "py", "js", "ts", "html", "css", "xml", "yaml", "yml":
            return .text
        default: return .unsupported
        }
    }
}

// MARK: - Stale answers

/// One generation per conversation. A turn remembers the generation it started in; "new
/// conversation" or closing the chat calls `reset()`, so the tail of an answer that is still
/// arriving from the old process is dropped instead of landing in the next conversation.
struct ChatTurnToken {
    private(set) var generation: Int = 0

    init() {}

    mutating func reset() {
        generation &+= 1
    }

    func accepts(_ generation: Int) -> Bool {
        generation == self.generation
    }
}
