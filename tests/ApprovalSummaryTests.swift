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
