import Foundation

/// What a session's row says it did, in French, short (Task 27, Baptiste on 9 October 2026: « trop
/// d'info inutile, je veux que ce soit user friendly »): a tool call as a verb and its object, a
/// prompt as its first line, never an id (a UUID, a long hex or base64 token) and never raw JSON.
@main
enum ActionTextTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("files_are_read_created_and_modified_by_their_name", filesAreReadCreatedAndModifiedByTheirName),
            ("a_file_tool_without_a_path_says_a_file", aFileToolWithoutAPathSaysAFile),
            ("a_command_is_its_first_word_and_a_short_argument", aCommandIsItsFirstWordAndAShortArgument),
            ("a_long_command_is_cut_on_a_word", aLongCommandIsCutOnAWord),
            ("a_command_skips_cd_and_variables", aCommandSkipsCdAndVariables),
            ("a_command_never_shows_json_or_an_id", aCommandNeverShowsJSONOrAnId),
            ("searches_quote_their_pattern", searchesQuoteTheirPattern),
            ("the_web_says_its_query_or_its_domain", theWebSaysItsQueryOrItsDomain),
            ("a_subagent_says_its_description", aSubagentSaysItsDescription),
            ("tasks_and_questions_have_their_sentence", tasksAndQuestionsHaveTheirSentence),
            ("an_unknown_tool_is_used", anUnknownToolIsUsed),
            ("mcp_tools_get_a_verb_an_object_and_their_server", mcpToolsGetAVerbAnObjectAndTheirServer),
            ("mcp_verbs_follow_the_tool_s_prefix", mcpVerbsFollowTheToolsPrefix),
            ("mcp_create_says_a_new_one", mcpCreateSaysANewOne),
            ("an_mcp_server_that_is_an_id_is_not_named", anMCPServerThatIsAnIdIsNotNamed),
            ("an_mcp_tool_drops_its_server_s_own_name", anMCPToolDropsItsServersOwnName),
            ("an_mcp_verb_at_the_end_of_the_tool_counts", anMCPVerbAtTheEndOfTheToolCounts),
            ("an_mcp_tool_without_a_known_verb_is_used", anMCPToolWithoutAKnownVerbIsUsed),
            ("mcp_server_names_are_humanized", mcpServerNamesAreHumanized),
            ("ids_are_recognised", idsAreRecognised),
            ("words_and_short_numbers_are_not_ids", wordsAndShortNumbersAreNotIds),
            ("clean_strips_ids_from_a_text", cleanStripsIdsFromAText),
            ("a_date_led_name_is_no_id", aDateLedNameIsNoId),
            ("an_end_stops_before_raw_json", anEndStopsBeforeRawJSON),
            ("a_prompt_is_its_first_line", aPromptIsItsFirstLine),
            ("a_json_or_blank_prompt_is_nothing", aJSONOrBlankPromptIsNothing),
            ("a_question_is_asked_to_you", aQuestionIsAskedToYou),
            ("no_em_dash_anywhere", noEmDashAnywhere),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Action text: \(cases.count) cases passed")
    }

    static func describe(_ tool: String, _ input: [String: Any] = [:]) -> String {
        ActionText.describe(tool: tool, input: input)
    }

    static func expect(_ got: String, _ expected: String, _ what: String) {
        precondition(got == expected, "\(what): expected « \(expected) », got « \(got) »")
    }

    // MARK: - Files

    static func filesAreReadCreatedAndModifiedByTheirName() {
        expect(describe("Read", ["file_path": "/Users/me/projets/site/README.md"]), "Lit README.md", "Read")
        expect(describe("Write", ["file_path": "/Users/me/projets/site/src/app.ts"]), "Crée app.ts", "Write")
        expect(describe("Edit", ["file_path": "/Users/me/projets/site/index.html", "old_string": "a"]),
               "Modifie index.html", "Edit")
        expect(describe("MultiEdit", ["file_path": "Sources/Main.swift", "edits": []]), "Modifie Main.swift",
               "MultiEdit, relative path")
        expect(describe("NotebookEdit", ["notebook_path": "/tmp/analyse.ipynb"]), "Modifie analyse.ipynb",
               "NotebookEdit")
        expect(describe("LS", ["path": "/Users/me/projets/site/"]), "Liste site", "LS, trailing slash")
    }

    static func aFileToolWithoutAPathSaysAFile() {
        expect(describe("Read"), "Lit un fichier", "Read without a path")
        expect(describe("Write", ["file_path": 42]), "Crée un fichier", "a path that is not text")
        expect(describe("Edit", ["file_path": "/"]), "Modifie un fichier", "a path with no name")
        // A file named by an id only: the id is never shown.
        expect(describe("Read", ["file_path": "/Users/me/.claude/projects/x/96310fe8-60b7-452f-8cd7-a68a842ae8af"]),
               "Lit un fichier", "a file named by a UUID")
        expect(describe("LS"), "Liste un dossier", "LS without a path")
    }

    // MARK: - Commands

    static func aCommandIsItsFirstWordAndAShortArgument() {
        expect(describe("Bash", ["command": "npm test"]), "Exécute npm test", "a short command")
        expect(describe("Bash", ["command": "git status"]), "Exécute git status", "git")
        expect(describe("Bash", ["command": "/usr/bin/python3 -m pytest"]), "Exécute python3 -m pytest",
               "the first word by its name, not its path")
        expect(describe("Bash", ["command": "swift build\nswift test"]), "Exécute swift build",
               "the first line only")
        expect(describe("Bash", ["command": "  "]), "Exécute une commande", "a blank command")
        expect(describe("Bash"), "Exécute une commande", "no command")
    }

    static func aLongCommandIsCutOnAWord() {
        let text = describe("Bash", ["command": "xcodebuild -scheme NotchBuddy -configuration Debug build"])
        expect(text, "Exécute xcodebuild -scheme NotchBuddy…", "cut on a word")
        let shown = text.dropFirst("Exécute ".count)
        precondition(shown.count <= ActionText.commandLimit + 2, "about 30 characters, got \(shown.count)")
        let long = "averyveryveryveryverylongcommandnamewithoutspaces"
        expect(describe("Bash", ["command": long + " --flag"]),
               "Exécute " + long.prefix(ActionText.commandLimit - 1) + "…", "a first word longer than the limit")
    }

    static func aCommandSkipsCdAndVariables() {
        expect(describe("Bash", ["command": "cd /Users/me/projets/site && npm run build"]),
               "Exécute npm run build", "cd before && is skipped")
        expect(describe("Bash", ["command": "cd app; cd web; NODE_ENV=test npx vitest run"]),
               "Exécute npx vitest run", "several cd and a variable")
        expect(describe("Bash", ["command": "cd /tmp"]), "Exécute cd tmp", "a lone cd stays, by the folder's name")
    }

    static func aCommandNeverShowsJSONOrAnId() {
        expect(describe("Bash", ["command": #"curl -X POST -d '{"a":1}' https://api.example.com"#]),
               "Exécute curl -X POST -d…", "JSON stops the command")
        expect(describe("Bash", ["command": "git show 6bb0d00c8f1e2a3b4c5d6e7f8091a2b3c4d5e6f7"]),
               "Exécute git show", "a commit hash is dropped")
        expect(describe("Bash", ["command": "claude --resume 96310fe8-60b7-452f-8cd7-a68a842ae8af"]),
               "Exécute claude --resume", "a UUID is dropped")
    }

    // MARK: - Searches, web, agents

    static func searchesQuoteTheirPattern() {
        expect(describe("Grep", ["pattern": "func activate", "path": "Sources"]), "Cherche « func activate »", "Grep")
        expect(describe("Glob", ["pattern": "**/*.swift"]), "Cherche « **/*.swift »", "Glob")
        expect(describe("Grep", ["pattern": "a very long pattern that goes on and on and on"]),
               "Cherche « a very long pattern that goes on and on… »", "a long pattern is cut on a word")
        expect(describe("Grep"), "Cherche dans les fichiers", "Grep without a pattern")
        expect(describe("Glob"), "Cherche des fichiers", "Glob without a pattern")
    }

    static func theWebSaysItsQueryOrItsDomain() {
        expect(describe("WebSearch", ["query": "SwiftUI scrollTransition threshold"]),
               "Cherche sur le web : SwiftUI scrollTransition threshold", "WebSearch")
        expect(describe("WebFetch", ["url": "https://www.code.claude.com/docs/en/vs-code?x=1", "prompt": "lis"]),
               "Lit code.claude.com", "WebFetch, without www")
        expect(describe("WebFetch", ["url": "pas une adresse"]), "Lit une page web", "an address without a host")
        expect(describe("WebSearch"), "Cherche sur le web", "WebSearch without a query")
    }

    static func aSubagentSaysItsDescription() {
        expect(describe("Task", ["description": "Explore the codebase", "prompt": "…"]),
               "Lance un sous-agent : Explore the codebase", "Task")
        expect(describe("Agent", ["description": "Revue du code"]), "Lance un sous-agent : Revue du code", "Agent")
        expect(describe("Task"), "Lance un sous-agent", "without a description")
    }

    static func tasksAndQuestionsHaveTheirSentence() {
        expect(describe("TodoWrite", ["todos": [["content": "x"]]]), "Met à jour sa liste de tâches", "TodoWrite")
        expect(describe("AskUserQuestion", ["questions": []]), "Te pose une question", "AskUserQuestion")
    }

    static func anUnknownToolIsUsed() {
        expect(describe("ExitPlanMode"), "Utilise ExitPlanMode", "an unknown tool")
        expect(describe(""), "Utilise un outil", "no tool name")
        expect(describe("96310fe8-60b7-452f-8cd7-a68a842ae8af"), "Utilise un outil", "a tool named by an id")
    }

    // MARK: - MCP

    static func mcpToolsGetAVerbAnObjectAndTheirServer() {
        expect(describe("mcp__linear__list_issues"), "Liste les issues (Linear)", "the example of the brief")
        expect(describe("mcp__linear__get_issue", ["id": "KLA-12"]), "Lit l'issue (Linear)", "a singular object")
        expect(describe("mcp__github__get_pull_request"), "Lit la pull request (GitHub)", "a two-word object")
        expect(describe("mcp__google_calendar__list_events"), "Liste les événements (Google Calendar)",
               "an object translated")
    }

    static func mcpVerbsFollowTheToolsPrefix() {
        expect(describe("mcp__x__read_file"), "Lit le fichier (X)", "read_")
        expect(describe("mcp__x__fetch_page"), "Lit la page (X)", "fetch_")
        expect(describe("mcp__x__save_document"), "Crée un document (X)", "save_")
        expect(describe("mcp__x__update_project"), "Met à jour le projet (X)", "update_")
        expect(describe("mcp__x__delete_comment"), "Supprime le commentaire (X)", "delete_")
        expect(describe("mcp__x__search_threads"), "Cherche les fils (X)", "search_")
        expect(describe("mcp__x__query_meetings"), "Cherche les réunions (X)", "query_")
        expect(describe("mcp__x__send_message"), "Envoie le message (X)", "send_")
        expect(describe("mcp__x__list_widgets"), "Liste les widgets (X)", "an unknown plural object")
        expect(describe("mcp__x__get_widget_status"), "Lit widget status (X)", "an unknown compound object")
    }

    static func mcpCreateSaysANewOne() {
        expect(describe("mcp__claude_ai_Gmail__create_draft"), "Crée un brouillon (Gmail)", "create_ masculine")
        expect(describe("mcp__x__create_task"), "Crée une tâche (X)", "create_ feminine")
        expect(describe("mcp__x__create_issues"), "Crée des issues (X)", "create_ plural")
    }

    static func anMCPServerThatIsAnIdIsNotNamed() {
        // Baptiste's screenshot: « 96310fe8-60b7-452f-8cd7-a68a842ae8af · list_issues ».
        expect(describe("mcp__96310fe8-60b7-452f-8cd7-a68a842ae8af__list_issues"), "Liste les issues",
               "a connector known by its id")
        expect(describe("mcp__96310fe8-60b7-452f-8cd7-a68a842ae8af__search"), "Cherche", "a bare verb")
    }

    static func anMCPToolDropsItsServersOwnName() {
        expect(describe("mcp__notion__notion-search"), "Cherche dans Notion", "notion-search")
        expect(describe("mcp__claude_ai_Granola__query_granola_meetings"), "Cherche les réunions (Granola)",
               "the server's name inside the tool")
        expect(describe("mcp__slack__slack_send_message"), "Envoie le message (Slack)", "slack_send_message")
        expect(describe("mcp__notion__notion-fetch"), "Lit dans Notion", "a bare verb with a server")
        expect(describe("mcp__claude_ai_Notion__notion-fetch"), "Lit dans Notion", "the Notion connector")
    }

    /// The official GitHub MCP server names its tools `<object>_<verb>` (review of Task 27, Important 1).
    static func anMCPVerbAtTheEndOfTheToolCounts() {
        expect(describe("mcp__github__issue_read"), "Lit l'issue (GitHub)", "issue_read")
        expect(describe("mcp__github__issue_write"), "Modifie l'issue (GitHub)", "issue_write")
        expect(describe("mcp__github__pull_request_read"), "Lit la pull request (GitHub)", "pull_request_read")
        expect(describe("mcp__github__actions_list"), "Liste les actions (GitHub)", "actions_list")
    }

    static func anMCPToolWithoutAKnownVerbIsUsed() {
        expect(describe("mcp__Klayer_Back_Office__log_time"), "Utilise log time (Klayer Back Office)", "log_time")
        expect(describe("mcp__klayer__acknowledge_alert"), "Utilise acknowledge alert (Klayer)", "no verb known")
        expect(describe("mcp__96310fe8-60b7-452f-8cd7-a68a842ae8af__acknowledge_alert"), "Utilise acknowledge alert",
               "no verb known, a server known by its id")
        expect(describe("mcp__x__getWidgetStatus"), "Lit widget status (X)", "camelCase is split")
        expect(describe("mcp__x"), "Utilise x", "a malformed MCP name")
    }

    static func mcpServerNamesAreHumanized() {
        expect(ActionText.serverName("claude_ai_Google_Drive") ?? "nil", "Google Drive", "claude_ai_ stripped")
        expect(ActionText.serverName("plugin_klayer-delivery_linear") ?? "nil", "Linear", "a plugin's server")
        expect(ActionText.serverName("linear") ?? "nil", "Linear", "one word, capitalized")
        expect(ActionText.serverName("github") ?? "nil", "GitHub", "a brand keeps its capitals")
        expect(ActionText.serverName("GitHub") ?? "nil", "GitHub", "its own capitals kept")
        precondition(ActionText.serverName("96310fe8-60b7-452f-8cd7-a68a842ae8af") == nil, "an id is no name")
        precondition(ActionText.serverName("") == nil, "no name")
    }

    // MARK: - Ids

    static func idsAreRecognised() {
        for token in ["96310fe8-60b7-452f-8cd7-a68a842ae8af", "6bb0d00c8f1e2a3b4c5d", "a68a842ae8af",
                      "toolu_01XFDUDYJgAACzvnptvVoYEL", "aGVsbG8gd29ybGQgdGhpcyBpcyBiYXNlNjQ1",
                      "123456789012", "(96310fe8-60b7-452f-8cd7-a68a842ae8af)"] {
            precondition(ActionText.isId(token), "\(token) is an id")
        }
    }

    static func wordsAndShortNumbersAreNotIds() {
        for token in ["internationalization", "test_session_roster_2024_final", "MyComponentTest2Final",
                      "6bb0d00", "deadbeefcafe", "2026", "README.md", "KLA-12", "sess-1234-abcd"] {
            precondition(!ActionText.isId(token), "\(token) is not an id")
        }
    }

    static func cleanStripsIdsFromAText() {
        expect(ActionText.clean("96310fe8-60b7-452f-8cd7-a68a842ae8af · list_issues"), "list_issues",
               "an id and its separator go")
        expect(ActionText.clean("Session 96310fe8-60b7-452f-8cd7-a68a842ae8af.jsonl ouverte"), "Session .jsonl ouverte",
               "a UUID inside a word goes, the rest stays")
        expect(ActionText.clean("  J'ai   corrigé\tle bug  "), "J'ai corrigé le bug", "spaces collapsed")
        expect(ActionText.clean("toolu_01XFDUDYJgAACzvnptvVoYEL"), "", "nothing left")
    }

    /// Klayer names its folders by date first (review of Task 27, Minor 5).
    static func aDateLedNameIsNoId() {
        precondition(!ActionText.isId("2026-10-09-klayer-island"), "a date-led name is no id")
        precondition(!ActionText.isId("2026_10_09_compte_rendu.md"), "a date-led file name is no id")
        expect(describe("Read", ["file_path": "/Users/me/projets/2026-10-09-klayer-island"]),
               "Lit 2026-10-09-klayer-island", "a file named by its date")
        precondition(ActionText.isId("k3j9x0q2m8z7p1w4r6t5y8"), "a lower case token a quarter digits is still an id")
    }

    /// The row of a session that ended (Stop, StopFailure) stops before raw JSON: an API error's body
    /// and its request id never show (review of Task 27, Important 2).
    static func anEndStopsBeforeRawJSON() {
        let apiError = #"API Error: 529 {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"},"request_id":"req_011CSHwq3vP1y8bAmdZgzFv5"}"#
        expect(ActionText.end(apiError), "API Error: 529", "an API error")
        expect(ActionText.end("API Error: {\"type\":\"error\"}"), "API Error", "the separator before the JSON goes")
        expect(ActionText.end("Erreur [voir le détail]"), "Erreur", "a list too")
        expect(ActionText.end("Le résumé est prêt."), "Le résumé est prêt.", "a sentence stays whole")
        expect(ActionText.end(#"{"type":"error"}"#), "", "nothing but JSON: nothing")
        expect(ActionText.end("Fini 96310fe8-60b7-452f-8cd7-a68a842ae8af"), "Fini", "no id")
    }

    // MARK: - Prompts and questions

    static func aPromptIsItsFirstLine() {
        expect(ActionText.prompt("Corrige le calcul de la TVA\net ajoute un test") ?? "nil",
               "Corrige le calcul de la TVA", "the first line")
        expect(ActionText.prompt("\n\n  Relis   le contrat \n") ?? "nil", "Relis le contrat", "the first line with text")
        expect(ActionText.prompt("Reprends la session 96310fe8-60b7-452f-8cd7-a68a842ae8af") ?? "nil",
               "Reprends la session", "no id")
    }

    static func aJSONOrBlankPromptIsNothing() {
        precondition(ActionText.prompt(#"{"type":"text","text":"x"}"#) == nil, "raw JSON is no prompt")
        precondition(ActionText.prompt("[1, 2, 3]") == nil, "a JSON list is no prompt")
        precondition(ActionText.prompt("  \n ") == nil, "a blank prompt")
    }

    static func aQuestionIsAskedToYou() {
        expect(ActionText.question("Quelle base de données ?"), "Te pose une question : Quelle base de données ?",
               "a question")
        expect(ActionText.question("  "), "Te pose une question", "no text")
    }

    static func noEmDashAnywhere() {
        let samples = [describe("Read", ["file_path": "a.txt"]), describe("Bash", ["command": "ls"]),
                       describe("mcp__linear__list_issues"), describe("WebSearch", ["query": "q"]),
                       ActionText.question("q"), describe("TodoWrite"), describe("Task")]
        for text in samples {
            precondition(!text.contains("\u{2014}"), "no em dash in « \(text) »")
        }
    }
}
