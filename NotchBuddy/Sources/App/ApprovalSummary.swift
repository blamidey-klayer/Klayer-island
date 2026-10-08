import Foundation

/// What a permission card says about the request, on one line of text: the user approves what
/// they read, so the card names the command, file, address or argument, not only the tool. The
/// history of choices and the session row record the same text.
/// Foundation only, tested by scripts/test-approval-summary.sh.
enum ApprovalSummary {
    /// Longest compact JSON shown for a tool the card does not know, « … » included.
    static let jsonLimit = 200
    /// Longest MCP argument shown next to « server · tool ».
    static let shortArgument = 80

    /// - Bash: the command.
    /// - Write, Edit, MultiEdit, NotebookEdit, Read: the tool and the file, relative to `cwd` when
    ///   it is inside the project.
    /// - WebFetch: the tool and the URL. WebSearch: the tool and the query.
    /// - Grep, Glob: the tool, the pattern and the path (relative when inside the project).
    /// - MCP (`mcp__server__tool`): « server · tool », then its first short string argument.
    /// - Anything else, or an expected field missing: the tool and the compact JSON of its input,
    ///   cut at 200 characters. The tool alone when there is no input.
    static func text(tool: String, input: [String: Any], cwd: String) -> String {
        func string(_ key: String) -> String? {
            guard let value = input[key] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        switch tool {
        case "Bash":
            if let command = string("command") { return command }
        case "Write", "Edit", "MultiEdit", "NotebookEdit", "Read":
            if let file = string("file_path") ?? string("notebook_path") {
                return "\(tool) · \(relative(file, to: cwd))"
            }
        case "WebFetch":
            if let url = string("url") { return "\(tool) · \(url)" }
        case "WebSearch":
            if let query = string("query") { return "\(tool) · \(oneLine(query))" }
        case "Grep", "Glob":
            if let pattern = string("pattern") {
                guard let path = string("path") else { return "\(tool) · \(pattern)" }
                return "\(tool) · \(pattern) · \(relative(path, to: cwd))"
            }
        default:
            if tool.hasPrefix("mcp__") { return mcp(tool: tool, input: input) }
        }
        guard !input.isEmpty else { return tool }
        return "\(tool) · \(compactJSON(input))"
    }

    // MARK: - Parts

    /// `path` without the project folder when it lies inside it, unchanged otherwise.
    static func relative(_ path: String, to cwd: String) -> String {
        var base = cwd
        while base.count > 1, base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty, base != "/", path.hasPrefix(base + "/") else { return path }
        let rest = String(path.dropFirst(base.count + 1))
        return rest.isEmpty ? path : rest
    }

    /// « server · tool », then the first string argument (by key order) that fits on a short line.
    private static func mcp(tool: String, input: [String: Any]) -> String {
        let rest = String(tool.dropFirst("mcp__".count))
        let parts = rest.components(separatedBy: "__")
        let name = parts.count >= 2
            ? "\(parts[0]) · \(parts.dropFirst().joined(separator: "__"))"
            : rest
        let argument = input.keys.sorted().lazy
            .compactMap { input[$0] as? String }
            .map { oneLine($0) }
            .first { !$0.isEmpty && $0.count <= shortArgument }
        guard let argument else { return name }
        return "\(name) · \(argument)"
    }

    /// Line breaks and tabs become one space, ends trimmed.
    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Compact JSON with sorted keys and plain slashes, cut to `jsonLimit` characters with « … ».
    private static func compactJSON(_ input: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input,
                                                     options: [.sortedKeys, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8) else { return "…" }
        return json.count > jsonLimit ? String(json.prefix(jsonLimit - 1)) + "…" : json
    }
}
