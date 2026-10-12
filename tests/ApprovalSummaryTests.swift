import Foundation

/// What the permission card says about the request (review I4): the command of a Bash call, the
/// file, URL, query or pattern of the other tools, « server · tool » and a short argument for an
/// MCP tool, compact JSON for anything else. The history of choices records the same text.
@main
enum ApprovalSummaryTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("bash_shows_the_command", bashShowsTheCommand),
            ("file_tools_show_the_file_relative_to_the_project", fileToolsShowTheFileRelativeToTheProject),
            ("a_file_outside_the_project_keeps_its_full_path", aFileOutsideTheProjectKeepsItsFullPath),
            ("web_tools_show_the_url_or_the_query", webToolsShowTheURLOrTheQuery),
            ("grep_and_glob_show_the_pattern_and_the_path", grepAndGlobShowThePatternAndThePath),
            ("mcp_shows_server_tool_and_a_short_argument", mcpShowsServerToolAndAShortArgument),
            ("an_mcp_command_is_shown_even_when_long", anMCPCommandIsShownEvenWhenLong),
            ("anything_else_shows_compact_json_cut_at_200", anythingElseShowsCompactJSONCutAt200),
            ("a_missing_field_falls_back_to_json", aMissingFieldFallsBackToJSON),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Approval summary: \(cases.count) cases passed")
    }

    static let cwd = "/Users/louis/essai-a"

    static func check(_ got: String, _ expected: String, _ what: String) {
        precondition(got == expected, "\(what): expected « \(expected) », got « \(got) »")
    }

    static func bashShowsTheCommand() {
        check(ApprovalSummary.text(tool: "Bash", input: ["command": "npm test", "description": "Run tests"], cwd: cwd),
              "npm test", "Bash")
    }

    static func fileToolsShowTheFileRelativeToTheProject() {
        // The first scenario of the Mac checklist: « crée le fichier essai.txt » is a Write.
        check(ApprovalSummary.text(tool: "Write", input: ["file_path": "/Users/louis/essai-a/essai.txt", "content": "bonjour"], cwd: cwd),
              "Write · essai.txt", "Write")
        check(ApprovalSummary.text(tool: "Edit", input: ["file_path": "/Users/louis/essai-a/src/app.swift", "old_string": "a", "new_string": "b"], cwd: cwd + "/"),
              "Edit · src/app.swift", "Edit, cwd with a trailing slash")
        check(ApprovalSummary.text(tool: "MultiEdit", input: ["file_path": "/Users/louis/essai-a/README.md", "edits": []], cwd: cwd),
              "MultiEdit · README.md", "MultiEdit")
        check(ApprovalSummary.text(tool: "Read", input: ["file_path": "/Users/louis/essai-a/notes.md"], cwd: cwd),
              "Read · notes.md", "Read")
        check(ApprovalSummary.text(tool: "NotebookEdit", input: ["notebook_path": "/Users/louis/essai-a/analyse.ipynb", "new_source": "x"], cwd: cwd),
              "NotebookEdit · analyse.ipynb", "NotebookEdit names its file notebook_path")
    }

    static func aFileOutsideTheProjectKeepsItsFullPath() {
        check(ApprovalSummary.text(tool: "Write", input: ["file_path": "/Users/louis/.zshrc"], cwd: cwd),
              "Write · /Users/louis/.zshrc", "outside the project")
        check(ApprovalSummary.text(tool: "Write", input: ["file_path": "/Users/louis/essai-ab/x.txt"], cwd: cwd),
              "Write · /Users/louis/essai-ab/x.txt", "a sibling folder sharing the prefix is not inside")
        check(ApprovalSummary.text(tool: "Read", input: ["file_path": "/etc/hosts"], cwd: ""),
              "Read · /etc/hosts", "no cwd")
    }

    static func webToolsShowTheURLOrTheQuery() {
        check(ApprovalSummary.text(tool: "WebFetch", input: ["url": "https://docs.klayer.ai/guide", "prompt": "Résume"], cwd: cwd),
              "WebFetch · https://docs.klayer.ai/guide", "WebFetch")
        check(ApprovalSummary.text(tool: "WebSearch", input: ["query": "Claude Code hooks StopFailure"], cwd: cwd),
              "WebSearch · Claude Code hooks StopFailure", "WebSearch")
    }

    static func grepAndGlobShowThePatternAndThePath() {
        check(ApprovalSummary.text(tool: "Grep", input: ["pattern": "TODO", "path": "/Users/louis/essai-a/src", "output_mode": "content"], cwd: cwd),
              "Grep · TODO · src", "Grep with a path")
        check(ApprovalSummary.text(tool: "Grep", input: ["pattern": "func main"], cwd: cwd),
              "Grep · func main", "Grep without a path")
        check(ApprovalSummary.text(tool: "Glob", input: ["pattern": "**/*.swift", "path": "/tmp"], cwd: cwd),
              "Glob · **/*.swift · /tmp", "Glob outside the project")
    }

    static func mcpShowsServerToolAndAShortArgument() {
        check(ApprovalSummary.text(tool: "mcp__github__create_issue",
                                   input: ["body": String(repeating: "x", count: 500), "title": "Bouton cassé", "owner": 3],
                                   cwd: cwd),
              "github · create_issue · Bouton cassé", "the first short string argument, by key order, long ones skipped")
        check(ApprovalSummary.text(tool: "mcp__claude_ai_Slack__slack_send_message", input: [:], cwd: cwd),
              "claude_ai_Slack · slack_send_message", "no argument")
        check(ApprovalSummary.text(tool: "mcp__linear__save_issue", input: ["team": "  ", "title": "Ligne 1\nLigne 2"], cwd: cwd),
              "linear · save_issue · Ligne 1 Ligne 2", "blank strings skipped, on one line")
    }

    // 0.3.6, I3: his permissions for `mcp__terminal__run_in_terminal`. The card shows the command
    // itself, however long (its first 120 characters with « … »), never another argument (the
    // explanation, the folder); then a query, a URL, a path before any other argument.
    static func anMCPCommandIsShownEvenWhenLong() {
        let command = "npm run build -- --filter=contrats-fournisseurs-01 --report=ecarts-de-facturation && "
            + String(repeating: "node scripts/verifie.js ", count: 5)
        let long = String(command.prefix(200))
        precondition(long.count == 200)
        let text = ApprovalSummary.text(tool: "mcp__terminal__run_in_terminal",
                                        input: ["command": long, "explanation": "Run the tests",
                                                "cwd": "/Users/baptiste/Klayer-notif", "isBackground": false], cwd: cwd)
        let shown = text.replacingOccurrences(of: "terminal · run_in_terminal · ", with: "")
        precondition(text.hasPrefix("terminal · run_in_terminal · npm run build -- --filter"), "the command: « \(text) »")
        precondition(shown.count == 120 && shown.hasSuffix("…") && long.hasPrefix(String(shown.dropLast())),
                     "its first 119 characters and « … », got \(shown.count): « \(shown) »")
        check(ApprovalSummary.text(tool: "mcp__terminal__run_in_terminal",
                                   input: ["command": "npm test", "explanation": "Run the tests"], cwd: cwd),
              "terminal · run_in_terminal · npm test", "a short command, not the explanation (key order)")
        check(ApprovalSummary.text(tool: "mcp__terminal__run_in_terminal",
                                   input: ["command": "swift build\nswift test", "cwd": "/tmp"], cwd: cwd),
              "terminal · run_in_terminal · swift build swift test", "on one line, not the folder")
        check(ApprovalSummary.text(tool: "mcp__db__run", input: ["cmd": "VACUUM", "args": "a"], cwd: cwd),
              "db · run · VACUUM", "cmd")
        check(ApprovalSummary.text(tool: "mcp__notion__search", input: ["filter": "pages", "query": "Roadmap"], cwd: cwd),
              "notion · search · Roadmap", "a query before another argument")
        check(ApprovalSummary.text(tool: "mcp__fetch__fetch", input: ["format": "md", "url": "https://klayer.ai"], cwd: cwd),
              "fetch · fetch · https://klayer.ai", "a URL")
    }

    static func anythingElseShowsCompactJSONCutAt200() {
        check(ApprovalSummary.text(tool: "TodoWrite", input: ["todos": [["content": "a/b", "status": "pending"]]], cwd: cwd),
              #"TodoWrite · {"todos":[{"content":"a/b","status":"pending"}]}"#, "compact JSON, sorted keys, slashes kept")
        let long = ApprovalSummary.text(tool: "Task", input: ["prompt": String(repeating: "é", count: 400)], cwd: cwd)
        let json = long.replacingOccurrences(of: "Task · ", with: "")
        precondition(json.count == 200 && json.hasSuffix("…"), "JSON cut at 200 characters, « … » included, got \(json.count)")
        check(ApprovalSummary.text(tool: "ExitPlanMode", input: [:], cwd: cwd), "ExitPlanMode", "no input: the tool alone")
    }

    static func aMissingFieldFallsBackToJSON() {
        check(ApprovalSummary.text(tool: "Write", input: ["content": "x"], cwd: cwd),
              #"Write · {"content":"x"}"#, "Write without file_path")
        check(ApprovalSummary.text(tool: "Bash", input: ["description": "x"], cwd: cwd),
              #"Bash · {"description":"x"}"#, "Bash without command")
    }
}
