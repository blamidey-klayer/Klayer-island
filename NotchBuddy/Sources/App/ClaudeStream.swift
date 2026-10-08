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
/// warning) is ignored.
struct ClaudeStreamParser {
    private var buffer = Data()

    init() {}

    mutating func feed(_ data: Data) -> [ClaudeStreamEvent] {
        buffer.append(data)
        var events: [ClaudeStreamEvent] = []
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            events += Self.events(inLine: Data(buffer[start..<newline]))
            start = buffer.index(after: newline)
        }
        if start != buffer.startIndex {
            buffer = Data(buffer[start...])
        }
        return events
    }

    private static func events(inLine line: Data) -> [ClaudeStreamEvent] {
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
              let url = URL(string: link) else { return nil }
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
