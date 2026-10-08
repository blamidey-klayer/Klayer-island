import Foundation

/// The pure core of lot 4 (Foundation only): which `claude` binary to run, with which
/// environment and arguments, and how its `stream-json` output is read. The island's quick
/// chat and its Gmail draft both go through the user's own Claude Code.
@main
enum ClaudeCLITests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("locate_takes_the_first_executable_candidate", locateTakesTheFirstExecutableCandidate),
            ("environment_scrubs_keys_and_tags_the_process", environmentScrubsKeysAndTagsTheProcess),
            ("chat_arguments_have_no_tools", chatArgumentsHaveNoTools),
            ("draft_arguments_allow_only_the_draft_tool", draftArgumentsAllowOnlyTheDraftTool),
            ("auth_status", authStatus),
            ("attachment_kinds", attachmentKinds),
            ("user_line_is_one_json_line", userLineIsOneJSONLine),
            ("parser_joins_split_lines_and_skips_noise", parserJoinsSplitLinesAndSkipsNoise),
            ("parser_scans_once_and_drops_a_runaway_line", parserScansOnceAndDropsARunawayLine),
            ("gmail_tool_lookup", gmailToolLookup),
            ("gmail_draft_parse", gmailDraftParse),
            ("gmail_draft_preview", gmailDraftPreview),
            ("turn_token_rejects_stale_generations", turnTokenRejectsStaleGenerations),
            ("chat_attachment_by_kind", chatAttachmentByKind),
            ("chat_attachment_reads_the_file", chatAttachmentReadsTheFile),
            ("chat_message_carries_context_and_question", chatMessageCarriesContextAndQuestion),
            ("chat_transcript_keeps_the_latest_exchanges", chatTranscriptKeepsTheLatestExchanges),
            ("availability_from_auth_status", availabilityFromAuthStatus),
            ("shell_lookup_reads_an_executable_path", shellLookupReadsAnExecutablePath),
            ("chat_system_prompt", chatSystemPrompt),
            ("stderr_tail_and_last_line", stderrTailAndLastLine),
            ("chat_answer_folds_a_turn", chatAnswerFoldsATurn),
            ("chat_answer_trips_on_any_tool", chatAnswerTripsOnAnyTool),
            ("pdf_text_reads_pages_up_to_the_limit", pdfTextReadsPagesUpToTheLimit),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Claude CLI: \(cases.count) cases passed")
    }

    // MARK: - Helpers

    /// The value that follows `flag` in an argument list, nil when the flag is absent.
    static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func feedLine(_ parser: inout ClaudeStreamParser, _ json: String) -> [ClaudeStreamEvent] {
        parser.feed(Data((json + "\n").utf8))
    }

    // MARK: - Binary, environment, arguments

    static func locateTakesTheFirstExecutableCandidate() {
        let home = "/Users/test"
        precondition(ClaudeCLI.candidatePaths(home: home) == [
            "/Users/test/.local/bin/claude",
            "/Users/test/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/Users/test/.npm-global/bin/claude",
            "/Users/test/.bun/bin/claude",
        ], "the candidates keep the documented order")

        precondition(ClaudeCLI.locate(home: home, isExecutable: { $0 == "/opt/homebrew/bin/claude" })
                     == "/opt/homebrew/bin/claude")
        precondition(ClaudeCLI.locate(home: home, isExecutable: { _ in false }) == nil,
                     "no binary found must be nil, never a guessed path")
        let both: Set<String> = ["/usr/local/bin/claude", "/Users/test/.local/bin/claude"]
        precondition(ClaudeCLI.locate(home: home, isExecutable: { both.contains($0) })
                     == "/Users/test/.local/bin/claude",
                     "with several installs, the first candidate wins")
    }

    static func environmentScrubsKeysAndTagsTheProcess() {
        let scrubbed = [
            "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN",
            "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY",
            "ANTHROPIC_PROFILE",
        ]
        var base: [String: String] = [
            "HOME": "/Users/test", "USER": "test", "LANG": "fr_FR.UTF-8",
            "TMPDIR": "/var/folders/xx/T/", "PATH": "/usr/bin",
        ]
        for key in scrubbed { base[key] = "secret" }

        let binary = "/Users/test/.local/bin/claude"
        let env = ClaudeCLI.environment(from: base, binary: binary)
        for key in scrubbed {
            precondition(env[key] == nil, "\(key) must not reach the claude process")
        }
        precondition(env["HOME"] == "/Users/test", "HOME stays untouched")
        precondition(env["USER"] == "test" && env["LANG"] == "fr_FR.UTF-8"
                     && env["TMPDIR"] == "/var/folders/xx/T/", "every other variable stays untouched")
        precondition(env["KLAYER_ISLAND_INTERNAL"] == "1")
        precondition(env["PATH"] == "/Users/test/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
                     "binary folder first, then the standard folders, without duplicating /usr/bin")
        precondition(base["ANTHROPIC_API_KEY"] == "secret", "the caller's dictionary is not mutated")

        // The entries of the user's PATH that are not standard stay, after the standard ones.
        let nvm = ClaudeCLI.environment(from: ["PATH": "/usr/bin:/Users/test/.nvm/bin:/opt/homebrew/bin"],
                                        binary: "/Users/test/.npm-global/bin/claude")
        precondition(nvm["PATH"] == "/Users/test/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/Users/test/.nvm/bin",
                     "no entry twice, the user's own folders kept at the end")
        // No PATH at all, and a binary that already sits in a standard folder.
        let bare = ClaudeCLI.environment(from: [:], binary: "/opt/homebrew/bin/claude")
        precondition(bare["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
        precondition(bare["KLAYER_ISLAND_INTERNAL"] == "1")
    }

    static func chatArgumentsHaveNoTools() {
        let args = ClaudeCLI.chatArguments(systemPrompt: "Tu es Klay.")
        precondition(args == [
            "-p",
            "--model", "claude-haiku-5-5",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--tools", "",
            "--disallowedTools", "mcp__*",
            "--permission-mode", "dontAsk",
            "--no-session-persistence",
            "--settings", "{\"disableAllHooks\":true}",
            "--system-prompt", "Tu es Klay.",
        ], "the chat arguments are exactly the documented list")
        precondition(ClaudeCLI.model == "claude-haiku-5-5")
        precondition(value(after: "--tools", in: args) == "", "--tools takes an empty argument")
        precondition(value(after: "--disallowedTools", in: args) == "mcp__*")
        precondition(value(after: "--model", in: args) == "claude-haiku-5-5")
        precondition(args.contains("--no-session-persistence"))
        precondition(!args.contains("--allowedTools"), "the chat allows no tool")
    }

    static func draftArgumentsAllowOnlyTheDraftTool() {
        let args = ClaudeCLI.draftArguments(systemPrompt: "Rédige.")
        precondition(ClaudeCLI.gmailDraftTool == "mcp__claude_ai_Gmail__create_draft")
        precondition(Set(ClaudeCLI.gmailDeniedTools) == [
            "mcp__claude_ai_Gmail__send_message", "mcp__claude_ai_Gmail__reply",
            "mcp__claude_ai_Gmail__forward", "mcp__claude_ai_Gmail__update_draft",
            "mcp__claude_ai_Gmail__delete_draft",
        ], "sending, replying, forwarding and changing drafts are denied")

        guard let allowed = args.firstIndex(of: "--allowedTools"),
              let denied = args.firstIndex(of: "--disallowedTools") else {
            preconditionFailure("--allowedTools and --disallowedTools must both be present")
        }
        precondition(args[allowed + 1] == ClaudeCLI.gmailDraftTool)
        precondition(allowed + 2 == denied, "the draft tool is the only allowed tool")
        let deniedList = Array(args[(denied + 1)...])
        precondition(deniedList == ClaudeCLI.gmailDeniedTools,
                     "the denied list comes last and holds nothing but the denied tools (variadic flag)")
        for tool in ClaudeCLI.gmailDeniedTools {
            precondition(args[(denied + 1)...].contains(tool), "\(tool) must be denied")
            precondition(tool.hasPrefix("mcp__claude_ai_Gmail__"))
        }
        precondition(!deniedList.contains(ClaudeCLI.gmailDraftTool))
        precondition(value(after: "--setting-sources", in: args) == "local")
        precondition(value(after: "--tools", in: args) == "")
        precondition(value(after: "--permission-mode", in: args) == "dontAsk")
        precondition(value(after: "--model", in: args) == "claude-haiku-5-5")
        precondition(value(after: "--max-turns", in: args) == "3")
        precondition(value(after: "--system-prompt", in: args) == "Rédige.")
        precondition(value(after: "--settings", in: args) == "{\"disableAllHooks\":true}")
        precondition(value(after: "--output-format", in: args) == "stream-json")
        precondition(args.contains("-p") && args.contains("--verbose") && args.contains("--no-session-persistence"))
        precondition(!args.contains("--input-format"), "the request goes through stdin as plain text")
    }

    static func authStatus() {
        precondition(ClaudeCLI.authIsClaudeAI(statusJSON: Data("{\"loggedIn\":true,\"authMethod\":\"claude.ai\"}".utf8)))
        precondition(!ClaudeCLI.authIsClaudeAI(statusJSON: Data("{\"loggedIn\":true,\"authMethod\":\"api_key\"}".utf8)),
                     "an API key login does not give access to the claude.ai connectors")
        precondition(!ClaudeCLI.authIsClaudeAI(statusJSON: Data("oops".utf8)))
        precondition(!ClaudeCLI.authIsClaudeAI(statusJSON: Data()))
        precondition(!ClaudeCLI.authIsClaudeAI(statusJSON: Data("{\"loggedIn\":false}".utf8)))
        precondition(ClaudeCLI.installURL.absoluteString == "https://code.claude.com/docs/en/quickstart")
    }

    static func attachmentKinds() {
        precondition(ChatAttachmentKind.forExtension("PNG") == .image(mediaType: "image/png"))
        precondition(ChatAttachmentKind.forExtension("jpg") == .image(mediaType: "image/jpeg"))
        precondition(ChatAttachmentKind.forExtension("jpeg") == .image(mediaType: "image/jpeg"))
        precondition(ChatAttachmentKind.forExtension("gif") == .image(mediaType: "image/gif"))
        precondition(ChatAttachmentKind.forExtension("webp") == .image(mediaType: "image/webp"))
        precondition(ChatAttachmentKind.forExtension("pdf") == .pdf)
        precondition(ChatAttachmentKind.forExtension("md") == .text)
        for ext in ["txt", "csv", "json", "swift", "py", "js", "ts", "html", "css", "xml", "yaml", "yml"] {
            precondition(ChatAttachmentKind.forExtension(ext) == .text, "\(ext) is read as text")
        }
        precondition(ChatAttachmentKind.forExtension("zip") == .unsupported)
        precondition(ChatAttachmentKind.forExtension("") == .unsupported)
    }

    // MARK: - Stream

    static func userLineIsOneJSONLine() {
        let line = ClaudeStream.userLine(
            text: "Résume ça",
            images: [(mediaType: "image/png", base64: "aGVsbG8/+=")])
        precondition(line.hasSuffix("\n") && !line.dropLast().contains("\n"),
                     "one JSON per line, ended by a single newline")
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              object["type"] as? String == "user",
              object["parent_tool_use_id"] is NSNull,
              let message = object["message"] as? [String: Any],
              message["role"] as? String == "user",
              let content = message["content"] as? [[String: Any]] else {
            preconditionFailure("the line must read back as a user message")
        }
        precondition(content.count == 2)
        precondition(content[0]["type"] as? String == "image", "images come before the text")
        let source = content[0]["source"] as? [String: Any]
        precondition(source?["type"] as? String == "base64")
        precondition(source?["media_type"] as? String == "image/png")
        precondition(source?["data"] as? String == "aGVsbG8/+=")
        precondition(content[1]["type"] as? String == "text")
        precondition(content[1]["text"] as? String == "Résume ça")

        // User text is escaped by the JSON encoder, never concatenated: quotes, backslashes,
        // newlines, a lone CR and the two Unicode line separators must all stay inside the line.
        let hostile = "il a dit \"salut\" \\ puis\nune ligne\r\nautre\u{2028}sep\u{2029}fin 🙂"
        let hostileLine = ClaudeStream.userLine(text: hostile, images: [])
        precondition(hostileLine.hasSuffix("\n") && !hostileLine.dropLast().contains("\n"))
        precondition(!hostileLine.contains("\r") && !hostileLine.contains("\u{2028}") && !hostileLine.contains("\u{2029}"),
                     "no character a line reader could split on")
        let back = (try? JSONSerialization.jsonObject(with: Data(hostileLine.utf8))) as? [String: Any]
        let backContent = ((back?["message"] as? [String: Any])?["content"] as? [[String: Any]])
        precondition(backContent?.count == 1 && backContent?[0]["text"] as? String == hostile,
                     "the text survives the round trip unchanged")
    }

    static func parserJoinsSplitLinesAndSkipsNoise() {
        var parser = ClaudeStreamParser()

        // A text_delta cut in two reads yields one single event, and the delta is not lost.
        let delta = "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Bonjour\"}}}\n"
        let bytes = Array(delta.utf8)
        let cut = bytes.count / 2
        precondition(parser.feed(Data(bytes[..<cut])).isEmpty, "a partial line waits for its end")
        precondition(parser.feed(Data(bytes[cut...])) == [.textDelta("Bonjour")])

        // A multi-byte character split between two reads is not corrupted.
        let accent = "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"é🙂\"}}}\n"
        let accentBytes = Array(accent.utf8)
        let inside = accentBytes.firstIndex(of: 0xC3)! + 1
        precondition(parser.feed(Data(accentBytes[..<inside])).isEmpty)
        precondition(parser.feed(Data(accentBytes[inside...])) == [.textDelta("é🙂")])

        // Two lines in one read give two events, in order.
        let twice = delta + delta.replacingOccurrences(of: "Bonjour", with: "Klay")
        precondition(parser.feed(Data(twice.utf8)) == [.textDelta("Bonjour"), .textDelta("Klay")])

        // CRLF line ends: the `\r` is part of the line break, not of the JSON.
        let withoutBreak = String(delta.dropLast())
        precondition(parser.feed(Data((withoutBreak + "\r\n").utf8)) == [.textDelta("Bonjour")])
        // A `\r` and its `\n` split across two reads still make one line, read once.
        precondition(parser.feed(Data((withoutBreak + "\r").utf8)).isEmpty, "the line is not over before its \\n")
        precondition(parser.feed(Data("\n".utf8)) == [.textDelta("Bonjour")])

        // Noise: a CLI warning, an empty line, a JSON that is not an object, a JSON without a type.
        precondition(parser.feed(Data("warning: something went wrong\n".utf8)).isEmpty)
        precondition(parser.feed(Data("\n\n".utf8)).isEmpty)
        precondition(parser.feed(Data("[1,2,3]\n42\n".utf8)).isEmpty)
        precondition(parser.feed(Data("{\"hello\":1}\n".utf8)).isEmpty)
        // Events that are not read: other deltas, message_start, other system lines.
        precondition(feedLine(&parser, "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\"}}}").isEmpty)
        precondition(feedLine(&parser, "{\"type\":\"stream_event\",\"event\":{\"type\":\"message_start\"}}").isEmpty)
        precondition(feedLine(&parser, "{\"type\":\"system\",\"subtype\":\"hook_started\"}").isEmpty)
        // The noise did not break the stream: the next line is read.
        precondition(feedLine(&parser, "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"Bonjour\"}")
                     == [.turnEnded(isError: false, message: "Bonjour")])

        // Errors end the turn with their message.
        precondition(feedLine(&parser, "{\"type\":\"result\",\"is_error\":true,\"result\":\"x\"}")
                     == [.turnEnded(isError: true, message: "x")])
        precondition(feedLine(&parser, "{\"type\":\"result\",\"subtype\":\"error_max_turns\"}")
                     == [.turnEnded(isError: true, message: "error_max_turns")],
                     "an error subtype is never read as a success")

        // The init line gives the tools of the process.
        precondition(feedLine(&parser, "{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[\"mcp__claude_ai_Gmail__create_draft\",\"Read\"],\"model\":\"claude-haiku-5-5\"}")
                     == [.initialized(tools: ["mcp__claude_ai_Gmail__create_draft", "Read"])])
        precondition(feedLine(&parser, "{\"type\":\"system\",\"subtype\":\"init\"}") == [.initialized(tools: [])])

        // A complete assistant text, with a tool_use block of its own.
        let assistant = "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Voici\"},{\"type\":\"text\",\"text\":\" le texte\"},{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"Read\",\"input\":{\"path\":\"/tmp/a b\"}}]}}"
        let events = feedLine(&parser, assistant)
        precondition(events.count == 2)
        precondition(events[0] == .assistantText("Voici le texte"))
        if case .toolUse(let name, let inputJSON) = events[1] {
            precondition(name == "Read")
            let input = (try? JSONSerialization.jsonObject(with: Data(inputJSON.utf8))) as? [String: String]
            precondition(input == ["path": "/tmp/a b"], "the tool input is rewritten as JSON")
        } else {
            preconditionFailure("the second event must be the tool_use")
        }
        precondition(feedLine(&parser, "{\"type\":\"assistant\",\"message\":{\"content\":[]}}").isEmpty)

        // Tool results, whether the content is a string or a list of text blocks.
        precondition(feedLine(&parser, "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":\"ok\"}]}}")
                     == [.toolResult(text: "ok")])
        precondition(feedLine(&parser, "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":[{\"type\":\"text\",\"text\":\"{\\\"id\\\":\\\"r1\\\"}\"}]}]}}")
                     == [.toolResult(text: "{\"id\":\"r1\"}")])
        precondition(feedLine(&parser, "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"plain echo\"}}").isEmpty)
    }

    static func parserScansOnceAndDropsARunawayLine() {
        let delta = "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Bonjour\"}}}\n"
        let result = "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"fin\"}\n"

        // One byte per read (the scan resumes where it stopped): each line is read exactly once.
        var slow = ClaudeStreamParser()
        var events: [ClaudeStreamEvent] = []
        for byte in Array((delta + result + delta).utf8) {
            events += slow.feed(Data([byte]))
        }
        precondition(events == [.textDelta("Bonjour"), .turnEnded(isError: false, message: "fin"), .textDelta("Bonjour")],
                     "byte by byte gives the same events as a single read")
        precondition(ClaudeStreamParser.defaultMaxLineBytes == 8 * 1024 * 1024)

        // A line without a line break that outgrows the cap is dropped, the buffer is reset...
        var capped = ClaudeStreamParser(maxLineBytes: 64)
        precondition(capped.feed(Data(String(repeating: "x", count: 40).utf8)).isEmpty, "under the cap the line waits")
        precondition(capped.bufferedBytes == 40)
        precondition(capped.feed(Data(String(repeating: "y", count: 40).utf8)).isEmpty, "over the cap the line is dropped")
        precondition(capped.bufferedBytes == 0, "the buffer is reset once the unfinished line outgrows the cap")
        precondition(capped.feed(Data(String(repeating: "z", count: 1000).utf8)).isEmpty, "and nothing more is kept for it")
        precondition(capped.bufferedBytes == 0)
        // ...its tail is skipped up to its `\n`, even when that tail is a JSON line by itself...
        precondition(capped.feed(Data(("{\"type\":\"result\",\"result\":\"queue\"}\n").utf8)).isEmpty,
                     "the end of a dropped line never becomes an event")
        // ...and the stream goes on with the next line.
        let short = "{\"type\":\"result\",\"is_error\":true,\"result\":\"x\"}\n"
        precondition(short.utf8.count <= 64)
        precondition(capped.feed(Data(short.utf8)) == [.turnEnded(isError: true, message: "x")],
                     "a line that fits the cap is read")
        precondition(capped.bufferedBytes == 0, "a finished line leaves nothing in the buffer")

        // A complete line over the cap, in one read, is dropped like the others.
        var long = ClaudeStreamParser(maxLineBytes: 64)
        let tooLong = delta.replacingOccurrences(of: "Bonjour", with: String(repeating: "B", count: 200))
        precondition(long.feed(Data((tooLong + short).utf8)) == [.turnEnded(isError: true, message: "x")],
                     "the long line is dropped, the one after it is read")

        // A line of exactly the cap goes through (the limit is on the length, not off by one).
        var exact = ClaudeStreamParser(maxLineBytes: delta.utf8.count - 1)
        precondition(exact.feed(Data(delta.utf8)) == [.textDelta("Bonjour")])
        var oneOver = ClaudeStreamParser(maxLineBytes: delta.utf8.count - 2)
        precondition(oneOver.feed(Data(delta.utf8)).isEmpty)

        // The default cap does not get in the way of a long answer: one line of 1 MB is read.
        var big = ClaudeStreamParser()
        let bigDelta = delta.replacingOccurrences(of: "Bonjour", with: String(repeating: "B", count: 1_000_000))
        let pieces = Array(bigDelta.utf8)
        var bigEvents: [ClaudeStreamEvent] = []
        var offset = 0
        while offset < pieces.count {
            let end = min(offset + 65_536, pieces.count)
            bigEvents += big.feed(Data(pieces[offset..<end]))
            offset = end
        }
        precondition(bigEvents == [.textDelta(String(repeating: "B", count: 1_000_000))])
    }

    static func gmailToolLookup() {
        precondition(ClaudeStream.gmailDraftTool(in: ["mcp__claude_ai_Gmail__create_draft", "mcp__claude_ai_Gmail__send_message"])
                     == "mcp__claude_ai_Gmail__create_draft")
        precondition(ClaudeStream.gmailDraftTool(in: []) == nil)
        precondition(ClaudeStream.gmailDraftTool(in: ["Read", "mcp__claude_ai_Gmail__send_message"]) == nil)
        precondition(ClaudeStream.gmailDraftTool(in: ["mcp__claude_ai_Google_Calendar__create_event"]) == nil)
        // The exact connector name is not documented: any Gmail casing is found, but only a
        // claude.ai connector, never a server the user configured themselves.
        precondition(ClaudeStream.gmailDraftTool(in: ["Read", "mcp__claude_ai_gmail__create_draft"])
                     == "mcp__claude_ai_gmail__create_draft")
        precondition(ClaudeStream.gmailDraftTool(in: ["mcp__gmail__create_draft"]) == nil)
    }

    static func gmailDraftParse() {
        let ok = GmailDraft.parse(toolResult: "{\"id\":\"r1\",\"viewUrl\":\"https://mail.google.com/mail/u/0/#drafts/r1\"}")
        precondition(ok == GmailDraft(id: "r1", viewURL: URL(string: "https://mail.google.com/mail/u/0/#drafts/r1")!))
        let extra = GmailDraft.parse(toolResult: "{\"id\":\"r1\",\"threadId\":\"t9\",\"viewUrl\":\"https://mail.google.com/mail/u/0/#drafts/r1\"}")
        precondition(extra?.id == "r1")

        precondition(GmailDraft.parse(toolResult: "{\"id\":\"r1\",\"viewUrl\":\"http://evil.example\"}") == nil)
        precondition(GmailDraft.parse(toolResult: "{\"id\":\"r1\",\"viewUrl\":\"http://mail.google.com/mail/u/0/#drafts/r1\"}") == nil,
                     "https only")
        precondition(GmailDraft.parse(toolResult: "{\"id\":\"r1\",\"viewUrl\":\"https://mail.google.com.evil.example/x\"}") == nil,
                     "the host must be exactly mail.google.com")
        precondition(GmailDraft.parse(toolResult: "{\"id\":\"r1\",\"viewUrl\":\"https://mail.google.com@evil.example/x\"}") == nil)
        precondition(GmailDraft.parse(toolResult: "{\"id\":\"r1\",\"viewUrl\":\"https://evil.example/https://mail.google.com/\"}") == nil)
        precondition(GmailDraft.parse(toolResult: "{\"id\":\"r1\",\"viewUrl\":\"javascript:alert(1)\"}") == nil)
        precondition(GmailDraft.parse(toolResult: "{\"id\":\"r1\"}") == nil)
        precondition(GmailDraft.parse(toolResult: "{\"viewUrl\":\"https://mail.google.com/mail/u/0/#drafts/r1\"}") == nil)
        precondition(GmailDraft.parse(toolResult: "{\"id\":\"\",\"viewUrl\":\"https://mail.google.com/mail/u/0/#drafts/r1\"}") == nil)
        precondition(GmailDraft.parse(toolResult: "Draft created") == nil, "plain text is not a draft")
        precondition(GmailDraft.parse(toolResult: "") == nil)
    }

    static func gmailDraftPreview() {
        let line = "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"mcp__claude_ai_Gmail__create_draft\",\"input\":{\"to\":[\"a@b.fr\"],\"subject\":\"Devis\",\"body\":\"Bonjour\"}}]}}\n"
        var parser = ClaudeStreamParser()
        let events = parser.feed(Data(line.utf8))
        precondition(events.count == 1)
        guard case .toolUse(let name, let inputJSON) = events[0] else {
            preconditionFailure("the assistant event must give a toolUse")
        }
        precondition(name == ClaudeCLI.gmailDraftTool)
        precondition(GmailDraftPreview.parse(inputJSON: inputJSON)
                     == GmailDraftPreview(to: ["a@b.fr"], subject: "Devis", body: "Bonjour"))

        // Fields that the draft call may leave out, and input that is not a draft call.
        precondition(GmailDraftPreview.parse(inputJSON: "{\"subject\":\"Seul\"}")
                     == GmailDraftPreview(to: [], subject: "Seul", body: ""))
        precondition(GmailDraftPreview.parse(inputJSON: "{\"to\":\"a@b.fr\",\"subject\":\"S\",\"body\":\"B\"}")?.to == ["a@b.fr"])
        precondition(GmailDraftPreview.parse(inputJSON: "{}") == nil)
        precondition(GmailDraftPreview.parse(inputJSON: "not json") == nil)
    }

    static func turnTokenRejectsStaleGenerations() {
        var token = ChatTurnToken()
        let old = token.generation
        precondition(token.accepts(old))
        token.reset()
        precondition(!token.accepts(old), "a turn started before reset() is stale")
        let new = token.generation
        precondition(new != old && token.accepts(new))
        token.reset()
        precondition(!token.accepts(new) && !token.accepts(old))
    }

    // MARK: - Chat (Task 14)

    static func chatAttachmentByKind() {
        // An image up to 5 MB goes as base64 with its media type, its name as text.
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        guard case .ready(let image) = ChatAttachment.make(name: "capture.png", kind: .image(mediaType: "image/png"),
                                                           data: png, pdfText: nil) else {
            preconditionFailure("a small image is attached")
        }
        precondition(image.image == ChatImage(mediaType: "image/png", base64: png.base64EncodedString()))
        precondition(image.text == "Fichier : capture.png")
        precondition(ChatAttachment.maxImageBytes == 5 * 1024 * 1024)
        let atCap = Data(count: ChatAttachment.maxImageBytes)
        if case .refused = ChatAttachment.make(name: "a.jpg", kind: .image(mediaType: "image/jpeg"), data: atCap, pdfText: nil) {
            preconditionFailure("5 MB exactly is accepted")
        }
        precondition(ChatAttachment.make(name: "a.jpg", kind: .image(mediaType: "image/jpeg"),
                                         data: Data(count: ChatAttachment.maxImageBytes + 1), pdfText: nil)
                     == .refused("Cette image dépasse 5 Mo."))

        // A PDF goes as its text, cut at 200 000 characters, with a note when it is cut.
        precondition(ChatAttachment.maxPDFCharacters == 200_000)
        guard case .ready(let pdf) = ChatAttachment.make(name: "devis.pdf", kind: .pdf, data: nil,
                                                         pdfText: "Total : 12 €") else {
            preconditionFailure("a PDF with text is attached")
        }
        precondition(pdf.image == nil)
        precondition(pdf.text == "Fichier : devis.pdf\n\nTotal : 12 €")
        let long = String(repeating: "é", count: ChatAttachment.maxPDFCharacters + 10)
        guard case .ready(let cut) = ChatAttachment.make(name: "long.pdf", kind: .pdf, data: nil, pdfText: long) else {
            preconditionFailure("a long PDF is attached, cut")
        }
        precondition(cut.text == "Fichier : long.pdf\n\n" + String(repeating: "é", count: ChatAttachment.maxPDFCharacters)
                     + "\n\n[Texte coupé à 200 000 caractères.]",
                     "never more than 200 000 characters of the PDF, and the cut is said")
        let exact = String(repeating: "a", count: ChatAttachment.maxPDFCharacters)
        guard case .ready(let whole) = ChatAttachment.make(name: "x.pdf", kind: .pdf, data: nil, pdfText: exact) else {
            preconditionFailure("200 000 characters fit")
        }
        precondition(!whole.text.contains("coupé"), "a PDF that fits is not marked as cut")
        precondition(ChatAttachment.make(name: "scan.pdf", kind: .pdf, data: nil, pdfText: nil)
                     == .refused("Ce PDF ne contient pas de texte lisible."))
        precondition(ChatAttachment.make(name: "scan.pdf", kind: .pdf, data: nil, pdfText: " \n\t ")
                     == .refused("Ce PDF ne contient pas de texte lisible."))

        // UTF-8 text up to 200 KB goes inline, under its name.
        precondition(ChatAttachment.maxTextBytes == 200_000)
        guard case .ready(let text) = ChatAttachment.make(name: "notes.md", kind: .text,
                                                          data: Data("# Titre\nligne".utf8), pdfText: nil) else {
            preconditionFailure("a small text file is attached")
        }
        precondition(text.text == "Fichier : notes.md\n\n# Titre\nligne" && text.image == nil)
        if case .refused = ChatAttachment.make(name: "a.txt", kind: .text, data: Data(count: 200_000), pdfText: nil) {
            preconditionFailure("200 000 bytes exactly are accepted")
        }
        precondition(ChatAttachment.make(name: "a.txt", kind: .text, data: Data(repeating: 0x61, count: 200_001), pdfText: nil)
                     == .refused("Ce fichier dépasse 200 Ko."))
        precondition(ChatAttachment.make(name: "a.txt", kind: .text, data: Data([0xFF, 0xFE, 0x00, 0xC3]), pdfText: nil)
                     == .refused("Impossible de lire ce fichier."), "a text file that is not UTF-8 is refused")

        // Anything else, or a file that could not be read: refused, Claude is not started.
        precondition(ChatAttachment.make(name: "a.zip", kind: .unsupported, data: Data([1]), pdfText: nil)
                     == .refused("Ce type de fichier n'est pas pris en charge."))
        precondition(ChatAttachment.unsupportedMessage == "Ce type de fichier n'est pas pris en charge.")
        precondition(ChatAttachment.make(name: "a.png", kind: .image(mediaType: "image/png"), data: nil, pdfText: nil)
                     == .refused("Impossible de lire ce fichier."))
        precondition(ChatAttachment.make(name: "a.txt", kind: .text, data: nil, pdfText: nil)
                     == .refused("Impossible de lire ce fichier."))
    }

    static func chatAttachmentReadsTheFile() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("klayer-chat-attachment-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func file(_ name: String, _ data: Data) -> URL {
            let url = dir.appendingPathComponent(name)
            precondition(FileManager.default.createFile(atPath: url.path, contents: data))
            return url
        }

        let notes = file("Notes.TXT", Data("Bonjour Klay".utf8))
        guard case .ready(let text) = ChatAttachment.load(url: notes) else {
            preconditionFailure("a text file on disk is attached")
        }
        precondition(text.text == "Fichier : Notes.TXT\n\nBonjour Klay", "the kind comes from the extension, any case")

        let picture = file("photo.webp", Data([1, 2, 3]))
        guard case .ready(let image) = ChatAttachment.load(url: picture) else {
            preconditionFailure("an image on disk is attached")
        }
        precondition(image.image == ChatImage(mediaType: "image/webp", base64: Data([1, 2, 3]).base64EncodedString()))

        // Too big: refused from the size on disk.
        let big = file("big.log.txt", Data(repeating: 0x61, count: ChatAttachment.maxTextBytes + 1))
        precondition(ChatAttachment.load(url: big) == .refused("Ce fichier dépasse 200 Ko."))
        let huge = file("huge.png", Data(count: ChatAttachment.maxImageBytes + 1))
        precondition(ChatAttachment.load(url: huge) == .refused("Cette image dépasse 5 Mo."))

        // A PDF over 50 MB is refused from its size alone (a sparse file: nothing is read).
        precondition(ChatAttachment.maxPDFBytes == 50 * 1024 * 1024)
        let bigPDF = file("gros.pdf", Data())
        let handle = try! FileHandle(forWritingTo: bigPDF)
        try! handle.truncate(atOffset: UInt64(ChatAttachment.maxPDFBytes + 1))
        try! handle.close()
        precondition(ChatAttachment.load(url: bigPDF) == .refused("Ce PDF dépasse 50 Mo."))

        precondition(ChatAttachment.load(url: file("archive.zip", Data([1]))) == .refused(ChatAttachment.unsupportedMessage))
        precondition(ChatAttachment.load(url: dir.appendingPathComponent("gone.txt")) == .refused("Impossible de lire ce fichier."),
                     "a file that is gone is refused, never a crash")
    }

    static func chatMessageCarriesContextAndQuestion() {
        // The question alone.
        let plain = ChatOutgoing.compose(query: "Quelle heure ?", windowContext: nil, attachment: nil, transcript: nil)
        precondition(plain == ChatOutgoing(text: "Quelle heure ?", images: []))

        // The window the user attached, as text before the question.
        let window = ChatOutgoing.windowContext(appName: "Safari", title: "Devis Nortex", url: "https://exemple.fr/devis")
        precondition(window == "Contexte : fenêtre « Devis Nortex » de l'app Safari, URL https://exemple.fr/devis")
        precondition(ChatOutgoing.windowContext(appName: "Notes", title: "Courses", url: nil)
                     == "Contexte : fenêtre « Courses » de l'app Notes")
        precondition(!window.contains("\u{2014}"), "no em dash")

        // Everything at once: earlier exchanges, window, file, question, in that order; the
        // image of the file goes first in the line.
        let attachment = ChatAttachment(name: "capture.png", text: "Fichier : capture.png",
                                        image: ChatImage(mediaType: "image/png", base64: "QUJD"))
        let full = ChatOutgoing.compose(query: "Que vois-tu ?", windowContext: window, attachment: attachment,
                                        transcript: "Échanges précédents")
        precondition(full.text == "Échanges précédents\n\n\(window)\n\nFichier : capture.png\n\nQue vois-tu ?")
        precondition(full.images == [ChatImage(mediaType: "image/png", base64: "QUJD")])

        let line = full.line
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] else {
            preconditionFailure("the message reads back as a user line")
        }
        precondition(line.hasSuffix("\n") && !line.dropLast().contains("\n"), "one line on stdin")
        precondition(content.count == 2 && content[0]["type"] as? String == "image"
                     && content[1]["text"] as? String == full.text, "the image first, then the text")
    }

    static func chatTranscriptKeepsTheLatestExchanges() {
        precondition(ChatOutgoing.transcript([]) == nil, "a new conversation has no earlier exchange")
        precondition(ChatOutgoing.transcript([(fromUser: true, text: "  "), (fromUser: false, text: "")]) == nil,
                     "empty bubbles are not exchanges")
        let two = ChatOutgoing.transcript([(fromUser: true, text: "Bonjour"), (fromUser: false, text: "Salut !")])
        precondition(two == "Échanges précédents de cette conversation :\nUtilisateur : Bonjour\nKlay : Salut !")

        // Over the limit, the oldest exchanges go first; the newest one is always kept.
        let history = (1...50).map { (fromUser: $0 % 2 == 1, text: "message \($0) " + String(repeating: "x", count: 100)) }
        guard let cut = ChatOutgoing.transcript(history, limit: 1_000) else {
            preconditionFailure("a long history still gives a transcript")
        }
        precondition(cut.count <= 1_000 + 100, "about the limit, never the whole history")
        precondition(cut.contains("message 50 "), "the newest message is kept")
        precondition(!cut.contains("message 1 "), "the oldest message goes first")
        let lines = cut.split(separator: "\n").dropFirst()
        let numbers = lines.compactMap { line in line.split(separator: " ").dropFirst(3).first.flatMap { Int($0) } }
        precondition(numbers == numbers.sorted() && numbers.last == 50, "in their order: \(numbers)")
        precondition(ChatOutgoing.transcriptLimit == 20_000)

        // One message alone longer than the limit keeps its end.
        let single = ChatOutgoing.transcript([(fromUser: false, text: String(repeating: "a", count: 5_000) + "FIN")], limit: 1_000)
        precondition(single?.hasSuffix("FIN") == true && (single?.count ?? 0) <= 1_100)
    }

    static func availabilityFromAuthStatus() {
        let claudeAI = Data("{\"loggedIn\":true,\"authMethod\":\"claude.ai\",\"email\":\"a@b.fr\"}".utf8)
        precondition(ClaudeCLI.availability(afterAuthStatus: .finished(status: 0, output: claudeAI)) == .ready)
        precondition(ClaudeCLI.availability(afterAuthStatus: .launchFailed) == .missingCLI,
                     "a binary that cannot be started is a missing Claude Code")
        precondition(ClaudeCLI.availability(afterAuthStatus: .finished(status: 1, output: Data("{\"loggedIn\":false,\"authMethod\":\"none\"}".utf8)))
                     == .notLoggedIn)
        precondition(ClaudeCLI.availability(afterAuthStatus: .finished(status: 0, output: Data("{\"loggedIn\":true,\"authMethod\":\"api_key\"}".utf8)))
                     == .notLoggedIn, "only the claude.ai login counts")
        precondition(ClaudeCLI.availability(afterAuthStatus: .finished(status: 1, output: Data("oops".utf8))) == .notLoggedIn)
        // 126 and 127: the binary is there but cannot run (an npm install whose node is gone).
        precondition(ClaudeCLI.availability(afterAuthStatus: .finished(status: 127, output: Data())) == .missingCLI)
        precondition(ClaudeCLI.availability(afterAuthStatus: .finished(status: 126, output: Data())) == .missingCLI)
        precondition(ClaudeCLI.availability(afterAuthStatus: .timedOut) == nil,
                     "a check that timed out says nothing: not cached, the chat is tried")
        precondition(ClaudeCLI.authStatusArguments == ["auth", "status"])
        precondition(ClaudeCLI.authStatusTimeout == 5 && ClaudeCLI.shellLookupTimeout == 3)
        precondition(ClaudeCLI.chatIdleLimit == 600, "the chat process stops after 10 minutes without a message")
    }

    static func shellLookupReadsAnExecutablePath() {
        let isExec: (String) -> Bool = { $0 == "/Users/test/.volta/bin/claude" }
        precondition(ClaudeCLI.shellLookupArguments == ["-lc", "command -v claude"])
        precondition(ClaudeCLI.shellLookupPath(output: "/Users/test/.volta/bin/claude\n", isExecutable: isExec)
                     == "/Users/test/.volta/bin/claude")
        // A login shell may print its own lines first: the path is the last line that is one.
        precondition(ClaudeCLI.shellLookupPath(output: "Bienvenue\n  /Users/test/.volta/bin/claude  \n\n", isExecutable: isExec)
                     == "/Users/test/.volta/bin/claude")
        precondition(ClaudeCLI.shellLookupPath(output: "/opt/old/bin/claude\n/Users/test/.volta/bin/claude\n",
                                               isExecutable: { _ in true }) == "/Users/test/.volta/bin/claude",
                     "the answer of `command -v` is the last line the shell prints")
        precondition(ClaudeCLI.shellLookupPath(output: "", isExecutable: isExec) == nil)
        precondition(ClaudeCLI.shellLookupPath(output: "claude not found\n", isExecutable: { _ in true }) == nil)
        precondition(ClaudeCLI.shellLookupPath(output: "claude: aliased to npx claude\n", isExecutable: { _ in true }) == nil,
                     "an alias is not a binary")
        precondition(ClaudeCLI.shellLookupPath(output: "/usr/bin/claude\n", isExecutable: isExec) == nil,
                     "a path that is not executable is not taken")
    }

    static func chatSystemPrompt() {
        let named = ClaudeCLI.chatSystemPrompt(firstName: "Théo")
        precondition(named.hasPrefix("You are Klay, Théo's quick assistant in the notch of their Mac."))
        let neutral = ClaudeCLI.chatSystemPrompt(firstName: nil)
        precondition(neutral.hasPrefix("You are Klay, a quick assistant in the notch of the user's Mac."))
        for prompt in [named, neutral] {
            precondition(prompt.contains("no tools"), "Klay knows he has no tools")
            precondition(prompt.contains("cannot open files, browse the web or run anything"))
            precondition(prompt.contains("dropped"), "the dropped file is the only one he sees")
            precondition(prompt.contains("short") && prompt.contains("user's language"))
            precondition(prompt.contains("light Markdown") && prompt.contains("Avoid tables and big headings"))
            precondition(!prompt.lowercased().contains("web search access"), "no web search any more")
            precondition(!prompt.contains("\u{2014}") && !prompt.contains("\u{2013}"), "no em or en dash")
        }
    }

    static func stderrTailAndLastLine() {
        precondition(ClaudeCLI.stderrTailBytes == 4096)
        var tail = Data()
        tail = ClaudeCLI.appendingTail(tail, Data(repeating: 0x61, count: 3_000))
        tail = ClaudeCLI.appendingTail(tail, Data("\nError: Invalid API key\n".utf8))
        tail = ClaudeCLI.appendingTail(tail, Data(repeating: 0x62, count: 2_000) + Data("\nfatal: boom\n".utf8))
        precondition(tail.count == ClaudeCLI.stderrTailBytes, "only the last 4 KB are kept")
        precondition(String(decoding: tail, as: UTF8.self).hasSuffix("fatal: boom\n"))
        precondition(ClaudeCLI.lastErrorLine(tail) == "fatal: boom")
        precondition(ClaudeCLI.lastErrorLine(Data("Error: Invalid API key\n\n  \n".utf8)) == "Error: Invalid API key")
        precondition(ClaudeCLI.lastErrorLine(Data()) == nil)
        precondition(ClaudeCLI.lastErrorLine(Data(" \n\n".utf8)) == nil)
        let long = ClaudeCLI.lastErrorLine(Data(String(repeating: "z", count: 1_000).utf8)) ?? ""
        precondition(long.count == 200 && long.hasSuffix("…"), "a short error, cut at 200 characters")
    }

    // MARK: - The chat's answer (Task 14 review)

    static func delta(_ text: String) -> ClaudeStreamEvent { .textDelta(text) }

    static func chatAnswerFoldsATurn() {
        // Deltas fold into the text, the full text replaces them, the turn end keeps it.
        var answer = ChatAnswer()
        answer.read([.initialized(tools: []), delta("Bon"), delta("jour")])
        precondition(answer.text == "Bonjour" && answer.end == nil, "the bubble grows with each delta")
        answer.read([delta(" !"), .assistantText("Bonjour Théo !")])
        precondition(answer.text == "Bonjour Théo !", "the full text replaces the pieces")
        answer.read([.turnEnded(isError: false, message: "Bonjour Théo !")])
        precondition(answer.end == .answered("Bonjour Théo !"))
        // Nothing after the end of the turn changes it.
        answer.read([delta("trop tard"), .turnEnded(isError: true, message: "x")])
        precondition(answer.text == "Bonjour Théo !" && answer.end == .answered("Bonjour Théo !"))

        // Events after the end in the same read are ignored too.
        var same = ChatAnswer()
        same.read([delta("Oui"), .turnEnded(isError: false, message: nil), delta("encore")])
        precondition(same.text == "Oui" && same.end == .answered("Oui"))

        // No delta and no full text: the result text is the answer.
        var fallback = ChatAnswer()
        fallback.read([.turnEnded(isError: false, message: "Réponse du résultat")])
        precondition(fallback.text == "Réponse du résultat" && fallback.end == .answered("Réponse du résultat"))

        // Nothing at all, or blank text: an empty answer.
        var empty = ChatAnswer()
        empty.read([delta("  \n"), .turnEnded(isError: false, message: " ")])
        precondition(empty.end == .empty)
        precondition(ChatAnswer.emptyMessage == "Claude n'a rien répondu.")

        // An error keeps its message; a blank one leaves it to the caller (stderr line).
        var failed = ChatAnswer()
        failed.read([delta("début"), .turnEnded(isError: true, message: "API Error: overloaded")])
        precondition(failed.end == .failed("API Error: overloaded") && failed.text == "début")
        var silent = ChatAnswer()
        silent.read([.turnEnded(isError: true, message: "  ")])
        precondition(silent.end == .failed(nil))

        // Read through the parser, line by line, as ChatSession does.
        var parser = ClaudeStreamParser()
        var streamed = ChatAnswer()
        let lines = [
            "{\"type\":\"system\",\"subtype\":\"init\",\"tools\":[]}",
            "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Sa\"}}}",
            "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"lut\"}}}",
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Salut\"}]}}",
            "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"Salut\"}",
        ]
        for line in lines { streamed.read(feedLine(&parser, line)) }
        precondition(streamed.end == .answered("Salut"))
    }

    static func chatAnswerTripsOnAnyTool() {
        precondition(ChatAnswer.toolsMessage == "Le chat a reçu des outils : arrêt par sécurité.")
        // The process says it has a tool: stopped before any text is kept.
        var offered = ChatAnswer()
        offered.read([.initialized(tools: ["Read"]), delta("je lis le fichier")])
        precondition(offered.end == .toolsOffered && offered.text.isEmpty, "a listed tool stops the turn at once")
        var mcp = ChatAnswer()
        mcp.read([.initialized(tools: ["mcp__claude_ai_Gmail__create_draft"])])
        precondition(mcp.end == .toolsOffered, "a connector tool too")
        // The model calls a tool, or a tool answers: stopped, whatever came before.
        var used = ChatAnswer()
        used.read([delta("Voyons"), .toolUse(name: "Bash", inputJSON: "{}"), .turnEnded(isError: false, message: "ok")])
        precondition(used.end == .toolsOffered && used.text == "Voyons")
        var result = ChatAnswer()
        result.read([.toolResult(text: "contenu")])
        precondition(result.end == .toolsOffered)
        // No tool, or only EndConversation (it only ends the conversation, reads and changes
        // nothing, and no flag can remove it while another tool remains): no trip.
        var none = ChatAnswer()
        none.read([.initialized(tools: []), .initialized(tools: ["EndConversation"]), delta("ok"),
                   .turnEnded(isError: false, message: nil)])
        precondition(none.end == .answered("ok"))
        for event: ClaudeStreamEvent in [.initialized(tools: ["Read"]), .toolUse(name: "x", inputJSON: "{}"),
                                         .toolResult(text: "")] {
            precondition(ChatAnswer.breaksNoToolRule(event), "\(event) breaks the no-tool rule")
        }
        for event: ClaudeStreamEvent in [.initialized(tools: []), .initialized(tools: ["EndConversation"]),
                                         delta("a"), .assistantText("a"), .turnEnded(isError: true, message: nil)] {
            precondition(!ChatAnswer.breaksNoToolRule(event), "\(event) is not a tool")
        }
    }

    static func pdfTextReadsPagesUpToTheLimit() {
        // Pages are joined, a page without text is skipped.
        var asked: [Int] = []
        let short = ChatAttachment.pdfText(pageCount: 3, limit: 100, page: { index in
            asked.append(index)
            return ["Page un", nil, "Page trois"][index]
        }, isCancelled: { false })
        precondition(short == "Page un\n\nPage trois" && asked == [0, 1, 2])

        // A long PDF stops being read once past the limit: one character more than the limit
        // is kept, so the attachment knows it was cut.
        asked = []
        let long = ChatAttachment.pdfText(pageCount: 1_000, limit: 25, page: { index in
            asked.append(index)
            return String(repeating: "x", count: 10)
        }, isCancelled: { false })
        precondition(asked == [0, 1, 2], "pages after the limit are never read, got \(asked)")
        precondition(long == "xxxxxxxxxx\n\nxxxxxxxxxx\n\nxx", "limit + 1 characters, separators counted, got \(long ?? "nil")")

        // With the real limit, the text handed to the attachment is cut there and said so.
        let pages = ChatAttachment.pdfText(pageCount: 30, page: { _ in String(repeating: "a", count: 10_000) },
                                           isCancelled: { false })
        precondition(pages?.count == ChatAttachment.maxPDFCharacters + 1)
        guard case .ready(let attached) = ChatAttachment.make(name: "p.pdf", kind: .pdf, data: nil, pdfText: pages) else {
            preconditionFailure("attached")
        }
        precondition(attached.text.hasSuffix("\n\n[Texte coupé à 200 000 caractères.]"))

        // Exactly the limit: the whole text, nothing extra, so nothing is marked as cut.
        let exact = ChatAttachment.pdfText(pageCount: 2, limit: 22, page: { _ in String(repeating: "b", count: 10) },
                                           isCancelled: { false })
        precondition(exact == String(repeating: "b", count: 10) + "\n\n" + String(repeating: "b", count: 10))

        // A reset cancels the read between two pages.
        var calls = 0
        let cancelled = ChatAttachment.pdfText(pageCount: 10, limit: 1_000, page: { _ in
            calls += 1
            return "page"
        }, isCancelled: { calls >= 2 })
        precondition(cancelled == nil && calls == 2, "no page is read once cancelled")

        // No page at all: no text.
        precondition(ChatAttachment.pdfText(pageCount: 0, page: { _ in "x" }, isCancelled: { false }) == "")
    }
}
