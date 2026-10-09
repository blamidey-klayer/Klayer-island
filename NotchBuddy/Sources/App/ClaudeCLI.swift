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

// MARK: - The quick chat: availability, binary lookup, prompt, errors (Task 14)

/// What the quick chat can do on this Mac. `missingCLI`: no `claude` binary, or one that
/// cannot be started. `notLoggedIn`: Claude Code runs but is not logged in with a claude.ai
/// account.
enum ChatAvailability: Equatable, Sendable {
    case ready
    case missingCLI
    case notLoggedIn
}

/// How a short command (`claude auth status`, the login shell lookup) ended.
enum ShortRunOutcome: Equatable, Sendable {
    /// The executable could not be started.
    case launchFailed
    /// Stopped by the island after its time limit.
    case timedOut
    /// Exited on its own, with what it printed on stdout.
    case finished(status: Int32, output: Data)
}

extension ClaudeCLI {

    /// `claude auth status` prints the login as JSON (exit 0 logged in, 1 not).
    static let authStatusArguments = ["auth", "status"]
    static let authStatusTimeout: TimeInterval = 5

    /// When no usual install folder holds `claude`, a login shell is asked once where it is
    /// (a GUI app does not inherit the user's PATH).
    static let shellLookupArguments = ["-lc", "command -v claude"]
    static let shellLookupTimeout: TimeInterval = 3

    /// The chat process is stopped after 10 minutes without a message.
    static let chatIdleLimit: TimeInterval = 10 * 60

    /// What is kept of the chat process's stderr, to show a short error if it dies.
    static let stderrTailBytes = 4096

    /// The chat's availability after `claude auth status`. Nil when the check timed out: the
    /// answer is unknown, it is not cached and the chat is tried (a turn error then says why).
    /// Exit status 126 or 127: the binary is there but cannot run (an npm install whose
    /// `node` is gone), which is a missing Claude Code for the user.
    static func availability(afterAuthStatus outcome: ShortRunOutcome) -> ChatAvailability? {
        switch outcome {
        case .launchFailed:
            return .missingCLI
        case .timedOut:
            return nil
        case .finished(let status, let output):
            if status == 126 || status == 127 { return .missingCLI }
            return authIsClaudeAI(statusJSON: output) ? .ready : .notLoggedIn
        }
    }

    /// The path printed by `command -v claude` in a login shell: the last line that is an
    /// absolute path to an executable. Anything else (a greeting the shell prints, "not found",
    /// an alias) gives nil.
    static func shellLookupPath(output: String, isExecutable: (String) -> Bool) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") && isExecutable($0) }
            .last
    }

    /// Klay's system prompt in the quick chat. Greets the user by their macOS first name when
    /// there is one worth using (`resolveUserFirstName()`), and stays neutral otherwise.
    static func chatSystemPrompt(firstName: String?) -> String {
        let opening = if let firstName {
            "You are Klay, \(firstName)'s quick assistant in the notch of their Mac."
        } else {
            "You are Klay, a quick assistant in the notch of the user's Mac."
        }
        return """
        \(opening) \
        You have no tools: you cannot open files, browse the web or run anything. \
        The only file you can see is the one the user dropped on the notch, when its content is in their message. \
        Keep your answers short and answer in the user's language. \
        Use light Markdown when it helps: short paragraphs, bullet lists, **bold**, `inline code` and fenced code blocks. \
        Avoid tables and big headings: the chat window is small.
        """
    }

    /// `tail` followed by `chunk`, cut to its last `limit` bytes.
    static func appendingTail(_ tail: Data, _ chunk: Data, limit: Int = stderrTailBytes) -> Data {
        var joined = tail
        joined.append(chunk)
        return joined.count > limit ? Data(joined.suffix(limit)) : joined
    }

    /// The last non-blank line of what the process wrote on stderr, in French when it is a known
    /// error (`ClaudeErrorText`, which reads the whole line), then cut to 200 characters: what the
    /// user sees when the process dies during an answer. Nil when there is none.
    static func lastErrorLine(_ stderr: Data) -> String? {
        guard let line = String(decoding: stderr, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { !$0.isEmpty }) else { return nil }
        let shown = ClaudeErrorText.french(line)
        return shown.count > 200 ? String(shown.prefix(199)) + "…" : shown
    }
}

// MARK: - Known Claude Code errors, said in French

/// The error messages and subtypes Claude Code gives for a failed turn, said in French on the
/// chat's error note and on the email card. Anything else passes through unchanged. Only error
/// texts go through here, never what the model said in a turn that did not fail.
enum ClaudeErrorText {
    static let maxTurns = "Claude a atteint le nombre maximal d'étapes sans terminer."
    static let duringExecution = "Claude Code a rencontré une erreur pendant l'exécution."
    static let overloaded = "Les serveurs de Claude sont surchargés : réessaie dans un instant."
    static let rateLimited = "Trop de demandes en peu de temps : réessaie dans un instant."
    static let usageLimit = "Limite d'utilisation de ton forfait Claude atteinte : réessaie plus tard."
    /// The chat's not-logged-in notice.
    static let loggedOut = "Connecte Claude Code : ouvre un terminal, lance claude puis /login."

    static func french(_ message: String) -> String {
        let text = message.lowercased()
        let isError = text.contains("error")
        if text.contains("authentication_error") || text.contains("authentication failed")
            || text.contains("invalid api key") || text.contains("invalid bearer token")
            || text.contains("oauth token") || text.contains("please run /login")
            || text.contains("not logged in") || (isError && hasStatus(401, in: text)) {
            return loggedOut
        }
        if text.contains("usage limit") || text.contains("hit your limit") || isUsageWindowLimit(text) {
            return usageLimit
        }
        if text.contains("rate limit") || text.contains("rate_limit") || (isError && hasStatus(429, in: text)) {
            return rateLimited
        }
        if text.contains("overloaded") || (isError && hasStatus(529, in: text)) {
            return overloaded
        }
        if text.contains("error_max_turns") || text.contains("max turns") || text.contains("maximum number of turns") {
            return maxTurns
        }
        if text.contains("error_during_execution") {
            return duringExecution
        }
        return message
    }

    /// True when the HTTP status `code` stands in `text` as a whole number: « API Error: 401 »,
    /// never the 401 inside « 14010 » or « error_4011 ».
    private static func hasStatus(_ code: Int, in text: String) -> Bool {
        text.range(of: "\\b\(code)\\b", options: .regularExpression) != nil
    }

    /// « limit reached » for a usage window of the plan (« 5-hour limit reached », « Weekly limit
    /// reached », « Opus weekly limit reached »). A context or token limit is not a usage limit:
    /// it passes through as Claude Code says it; a rate limit has its own rule.
    private static func isUsageWindowLimit(_ text: String) -> Bool {
        guard text.contains("limit reached"), !text.contains("context"), !text.contains("token") else { return false }
        return ["5-hour", "hourly", "daily", "weekly", "session", "opus", "sonnet"].contains { text.contains($0) }
    }
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
