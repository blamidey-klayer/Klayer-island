import Foundation

// MARK: - Claude Code `stream-json`, both directions (lot 4)
//
// Foundation only. In: the user's messages as one JSON line each on the stdin of the chat
// process. Out: the lines that `claude -p --output-format stream-json --verbose` prints,
// read into a handful of events. The AppKit side drives this; it is tested on any machine.

enum ClaudeStream {

    /// One user message for `--input-format stream-json`: a single JSON line ended by `\n`,
    /// images first, then the text. The text is encoded by JSONSerialization, never pasted
    /// into a template, so quotes, backslashes and line breaks of what the user typed (or of
    /// a dropped file) cannot break the line. The two Unicode line separators are written as
    /// escapes too, because some line readers split on them.
    ///
    /// An empty `text` goes without a text block (the API refuses empty ones), so an empty text
    /// with no image gives a message with no content at all, which the API refuses as well:
    /// callers must not send it.
    static func userLine(text: String, images: [(mediaType: String, base64: String)]) -> String {
        var content: [[String: Any]] = images.map { image in
            [
                "type": "image",
                "source": ["type": "base64", "media_type": image.mediaType, "data": image.base64],
            ]
        }
        // The API refuses an empty text block: an image sent alone goes without one.
        if !text.isEmpty {
            content.append(["type": "text", "text": text])
        }
        let object: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": content],
            "parent_tool_use_id": NSNull(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.sortedKeys, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8) else {
            // Cannot happen for strings, NSNull and containers; never crash on it anyway.
            return "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[]},\"parent_tool_use_id\":null}\n"
        }
        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029") + "\n"
    }

    /// The Gmail "create a draft" tool among the tools of the process (`tools` of the init
    /// event). The connector name is not documented to the letter, so it is looked up: a
    /// claude.ai connector, with "gmail" in its name (any case), ending in `__create_draft`.
    static func gmailDraftTool(in tools: [String]) -> String? {
        tools.first {
            $0.hasPrefix("mcp__claude_ai_")
                && $0.lowercased().contains("gmail")
                && $0.hasSuffix("__create_draft")
        }
    }

    /// A JSON object as compact text (stable key order), "{}" when it cannot be written.
    fileprivate static func jsonText(_ value: Any?) -> String {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value,
                                                     options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

// MARK: - Events

enum ClaudeStreamEvent: Equatable {
    /// The process is up: the tools it can use (the Gmail connector shows here or not at all).
    case initialized(tools: [String])
    /// A piece of the answer, as it is written (`--include-partial-messages`).
    case textDelta(String)
    /// The complete text of an assistant message, which replaces the pieces.
    case assistantText(String)
    /// The model calls a tool; `inputJSON` is its input as JSON text.
    case toolUse(name: String, inputJSON: String)
    /// What a tool answered.
    case toolResult(text: String)
    /// The turn is over, with its final text or its error message.
    case turnEnded(isError: Bool, message: String?)
}

/// Reads the output of `claude -p --output-format stream-json` as it comes. `feed` takes the
/// bytes of one read, which can stop anywhere (inside a line, inside a multi-byte character):
/// the incomplete end waits for the next call, and a line that is not a JSON object (a CLI
/// warning) is ignored. Lines end with `\n` or `\r\n`.
///
/// A line longer than `maxLineBytes` (8 MB by default) is dropped whole, so that a runaway
/// output without a line break cannot grow the buffer without end: the rest of that line is
/// skipped up to its `\n`, and the stream goes on with the next line.
struct ClaudeStreamParser {
    static let defaultMaxLineBytes = 8 * 1024 * 1024

    private let maxLineBytes: Int
    private var buffer = Data()
    /// Bytes at the start of `buffer` already searched for a line break (there is none in
    /// them): each `feed` only scans what is new, never the whole buffer again.
    private var scanned = 0
    /// True while the rest of an over-long line is being skipped.
    private var skippingLine = false

    init(maxLineBytes: Int = ClaudeStreamParser.defaultMaxLineBytes) {
        self.maxLineBytes = maxLineBytes
    }

    /// Bytes of the unfinished line kept for the next `feed` (0 after a dropped line).
    var bufferedBytes: Int { buffer.count }

    mutating func feed(_ data: Data) -> [ClaudeStreamEvent] {
        buffer.append(data)
        var events: [ClaudeStreamEvent] = []
        var start = buffer.startIndex
        var searchFrom = buffer.index(buffer.startIndex, offsetBy: scanned)
        while let newline = buffer[searchFrom...].firstIndex(of: 0x0A) {
            if skippingLine {
                skippingLine = false
            } else if newline - start <= maxLineBytes {
                events += Self.events(inLine: Data(buffer[start..<newline]))
            }
            start = buffer.index(after: newline)
            searchFrom = start
        }
        // What is left holds no line break: keep it, unless it is a runaway line.
        if skippingLine || buffer.endIndex - start > maxLineBytes {
            buffer = Data()
            scanned = 0
            skippingLine = true
        } else {
            if start != buffer.startIndex {
                buffer = Data(buffer[start...])
            }
            scanned = buffer.count
        }
        return events
    }

    private static func events(inLine rawLine: Data) -> [ClaudeStreamEvent] {
        // The `\r` of a `\r\n` line end belongs to the line break, not to the JSON.
        let line = rawLine.last == 0x0D ? Data(rawLine.dropLast()) : rawLine
        guard !line.isEmpty,
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = object["type"] as? String else { return [] }

        switch type {
        case "system":
            guard object["subtype"] as? String == "init" else { return [] }
            let tools = (object["tools"] as? [Any])?.compactMap { $0 as? String } ?? []
            return [.initialized(tools: tools)]

        case "stream_event":
            guard let event = object["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String, !text.isEmpty else { return [] }
            return [.textDelta(text)]

        case "assistant":
            guard let message = object["message"] as? [String: Any] else { return [] }
            if let text = message["content"] as? String {
                return text.isEmpty ? [] : [.assistantText(text)]
            }
            guard let blocks = message["content"] as? [[String: Any]] else { return [] }
            let text = blocks
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
            var events: [ClaudeStreamEvent] = text.isEmpty ? [] : [.assistantText(text)]
            for block in blocks where block["type"] as? String == "tool_use" {
                guard let name = block["name"] as? String else { continue }
                events.append(.toolUse(name: name, inputJSON: ClaudeStream.jsonText(block["input"])))
            }
            return events

        case "user":
            guard let message = object["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { return [] }
            return blocks
                .filter { $0["type"] as? String == "tool_result" }
                .map { .toolResult(text: resultText($0["content"])) }

        case "result":
            let subtype = object["subtype"] as? String ?? ""
            // An error subtype ("error_max_turns", "error_during_execution") is an error even
            // when the line carries no is_error: never read it as a success.
            let isError = (object["is_error"] as? Bool ?? false) || subtype.hasPrefix("error")
            var message = object["result"] as? String
            if message?.isEmpty ?? true {
                message = isError && !subtype.isEmpty ? subtype : nil
            }
            return [.turnEnded(isError: isError, message: message)]

        default:
            return []
        }
    }

    /// The text of a tool result, whether `content` is a string or a list of blocks (the text
    /// blocks are joined by a line break, anything else is ignored).
    private static func resultText(_ content: Any?) -> String {
        if let text = content as? String { return text }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }
}

// MARK: - The Gmail draft

/// What the Gmail connector answers to a draft creation: the draft id and the link that opens
/// it in Gmail.
struct GmailDraft: Equatable {
    let id: String
    let viewURL: URL

    /// Reads the tool result (JSON with `id` and `viewUrl`). The link is accepted only when
    /// it is an `https://mail.google.com/…` one (exact host, no credentials, standard port):
    /// the app opens it on a click, so whatever the model wrote there is never trusted.
    static func parse(toolResult: String) -> GmailDraft? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(toolResult.utf8))) as? [String: Any],
              let id = object["id"] as? String, !id.isEmpty,
              let link = object["viewUrl"] as? String,
              let parts = URLComponents(string: link),
              parts.scheme?.lowercased() == "https",
              parts.host?.lowercased() == "mail.google.com",
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              let url = URL(string: link),
              // The URL that is returned (and later opened) is checked again: the two parsers
              // must agree on scheme and host.
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "mail.google.com" else { return nil }
        return GmailDraft(id: id, viewURL: url)
    }
}

/// What the model asked the draft tool for: shown to the user as a preview of the draft.
struct GmailDraftPreview: Equatable {
    let to: [String]
    let subject: String
    let body: String

    /// Reads the input of the draft tool call (`to` is a list, a lone string is accepted).
    /// Nil when it is not a JSON object or carries none of the three fields.
    static func parse(inputJSON: String) -> GmailDraftPreview? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(inputJSON.utf8))) as? [String: Any],
              object["to"] != nil || object["subject"] != nil || object["body"] != nil else { return nil }
        var recipients: [String] = []
        if let list = object["to"] as? [Any] {
            recipients = list.compactMap { $0 as? String }
        } else if let one = object["to"] as? String {
            recipients = one.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return GmailDraftPreview(to: recipients,
                                 subject: object["subject"] as? String ?? "",
                                 body: object["body"] as? String ?? "")
    }
}

// MARK: - One answer of the quick chat (Task 14)

/// One answer of the quick chat, folded from the events of its turn. Foundation only, tested
/// by scripts/test-claude-cli.sh: ChatSession writes what this decides and nothing more.
///
/// The chat must have no tool. Its flags already remove them all (`ClaudeCLI.chatArguments`),
/// but the user's own permission rules still apply under `dontAsk`, so the answer also checks
/// for itself: a tool listed by the process, a tool call or a tool result ends the turn as
/// `toolsOffered`, and the caller stops the process.
struct ChatAnswer: Equatable {
    /// How a turn ended.
    enum End: Equatable {
        /// The text to keep in the bubble.
        case answered(String)
        /// A failed turn, with the CLI's message when it gave one, in French when it is a known
        /// error (nil: the caller says, from the last line of stderr or its own message).
        case failed(String?)
        /// The turn ended without any text.
        case empty
        /// The process has a tool or used one: stopped for safety.
        case toolsOffered
    }

    static let emptyMessage = "Claude n'a rien répondu."
    static let toolsMessage = "Le chat a reçu des outils : arrêt par sécurité."

    /// Listed without being a risk: EndConversation only ends the conversation, never reads or
    /// changes anything, and no flag can remove it while another tool remains (Claude Code
    /// tools reference). ToolSearch and WaitForMcpServers only load or wait for MCP tools, of
    /// which the chat has none (`--disallowedTools mcp__*`); a managed setting can keep tool
    /// search on. Tolerated in the `init` list by their exact names only: a call of any of them,
    /// or any tool result, still trips the check, and so does any other name.
    static let harmlessTools: Set<String> = ["EndConversation", "ToolSearch", "WaitForMcpServers"]

    /// The text the bubble shows so far.
    private(set) var text = ""
    /// Set once the turn is over; later events change nothing.
    private(set) var end: End?

    init() {}

    /// True when the event shows that the process has a tool, or used one.
    static func breaksNoToolRule(_ event: ClaudeStreamEvent) -> Bool {
        switch event {
        case .initialized(let tools):
            return tools.contains { !harmlessTools.contains($0) }
        case .toolUse, .toolResult:
            return true
        case .textDelta, .assistantText, .turnEnded:
            return false
        }
    }

    /// Reads the events of one stdout read, in order: deltas add to the text, a full text
    /// replaces it, the turn end decides the outcome (the result text stands in when no text
    /// came at all).
    mutating func read(_ events: [ClaudeStreamEvent]) {
        for event in events where end == nil {
            if Self.breaksNoToolRule(event) {
                end = .toolsOffered
                return
            }
            switch event {
            case .textDelta(let piece):
                text += piece
            case .assistantText(let whole):
                text = whole
            case .turnEnded(let isError, let message):
                let said = message.flatMap { Self.isBlank($0) ? nil : $0 }
                if isError {
                    // A known CLI error is said in French; an unknown one passes through.
                    end = .failed(said.map(ClaudeErrorText.french))
                } else if !Self.isBlank(text) {
                    end = .answered(text)
                } else if let said {
                    text = said
                    end = .answered(said)
                } else {
                    end = .empty
                }
            case .initialized, .toolUse, .toolResult:
                break
            }
        }
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
