import Foundation

// MARK: - What a session's row says it did (Task 27)
// Baptiste, 9 October 2026, on the home's list: « trop d'info inutile, je veux que ce soit user
// friendly ». The second line of a row is the last action in plain French, short, in the third
// person: « Lit README.md », « Exécute npm test », « Liste les issues (Linear) ». Never an id (a
// UUID, a long hex or base64 token), never raw JSON. Built from the hook's tool name and input,
// which Claude Code documents (hooks reference, PreToolUse); a tool it does not know is « Utilise
// <outil> ». Foundation only, French literals (the interface is French), tested by
// scripts/test-action-text.sh.

enum ActionText {
    /// Longest command shown after « Exécute », in characters (« … » included).
    static let commandLimit = 30
    /// Longest argument shown (a pattern, a query, a description), in characters (« … » included).
    static let argumentLimit = 40

    /// The action of a tool call, from the hook's `tool_name` and `tool_input`.
    static func describe(tool: String, input: [String: Any]) -> String {
        switch tool {
        case "Read":
            return fileAction("Lit", input["file_path"], fallback: "Lit un fichier")
        case "Write":
            return fileAction("Crée", input["file_path"], fallback: "Crée un fichier")
        case "Edit", "MultiEdit":
            return fileAction("Modifie", input["file_path"], fallback: "Modifie un fichier")
        case "NotebookEdit":
            return fileAction("Modifie", input["notebook_path"], fallback: "Modifie un notebook")
        case "LS":
            return fileAction("Liste", input["path"], fallback: "Liste un dossier")
        case "Bash":
            guard let command = (input["command"] as? String).flatMap(shortCommand) else {
                return "Exécute une commande"
            }
            return "Exécute " + command
        case "Grep":
            guard let pattern = argument(input["pattern"]) else { return "Cherche dans les fichiers" }
            return "Cherche « \(pattern) »"
        case "Glob":
            guard let pattern = argument(input["pattern"]) else { return "Cherche des fichiers" }
            return "Cherche « \(pattern) »"
        case "WebSearch":
            guard let query = argument(input["query"]) else { return "Cherche sur le web" }
            return "Cherche sur le web : " + query
        case "WebFetch":
            guard let host = webHost(input["url"]) else { return "Lit une page web" }
            return "Lit " + host
        case "Task", "Agent":
            guard let description = argument(input["description"]) else { return "Lance un sous-agent" }
            return "Lance un sous-agent : " + description
        case "TodoWrite":
            return "Met à jour sa liste de tâches"
        case "AskUserQuestion":
            return "Te pose une question"
        default:
            if let mcp = mcpAction(tool) { return mcp }
            let name = clean(tool)
            return name.isEmpty ? "Utilise un outil" : "Utilise " + name
        }
    }

    /// The line of a prompt: its first line with text, one run of spaces each, without ids. Nil for a
    /// blank prompt or raw JSON.
    static func prompt(_ text: String) -> String? {
        guard !looksLikeJSON(text) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let cleaned = clean(String(line))
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    /// The line of a question card: « Te pose une question : <question> ».
    static func question(_ text: String) -> String {
        let cleaned = prompt(text) ?? ""
        return cleaned.isEmpty ? "Te pose une question" : "Te pose une question : " + cleaned
    }

    // MARK: - Ids and JSON

    /// A token that only identifies something: a UUID, 12 hex characters or more with a digit (a
    /// commit, a long number), or an opaque token of 20 characters or more (base64, `toolu_…`) that
    /// mixes cases with 2 digits or more, or is a quarter digits with no word in it (3 letters or more
    /// between separators: « 2026-10-09-klayer-island » is a name). Surrounding punctuation is ignored.
    /// Words, file names and short references (« 6bb0d00 », « KLA-12 ») are not ids.
    static func isId(_ token: String) -> Bool {
        let core = token.trimmingCharacters(in: edgePunctuation)
        guard !core.isEmpty else { return false }
        if core.range(of: uuidPattern, options: .regularExpression) != nil,
           core.replacingOccurrences(of: uuidPattern, with: "", options: .regularExpression).isEmpty {
            return true
        }
        let digits = core.filter(\.isASCIIDigit).count
        if core.count >= 12, digits > 0, core.allSatisfy(\.isHexDigit), core.allSatisfy(\.isASCII) {
            return true
        }
        let opaqueAlphabet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/=_-")
        guard core.count >= 20, core.unicodeScalars.allSatisfy({ opaqueAlphabet.contains($0) }) else { return false }
        let upper = core.contains(where: \.isUppercase)
        let lower = core.contains(where: \.isLowercase)
        if upper && lower && digits >= 2 { return true }
        let hasWord = core.split(whereSeparator: { "+/=_-.".contains($0) })
            .contains { $0.count >= 3 && $0.allSatisfy(\.isLetter) }
        return digits * 4 >= core.count && !hasWord
    }

    /// `text` on one line, each run of spaces one space, without its ids: an id word goes, a UUID
    /// inside a word goes and the rest of the word stays. Separators left alone at an end go too.
    static func clean(_ text: String) -> String {
        var words: [String] = []
        for raw in text.split(whereSeparator: \.isWhitespace) {
            var word = String(raw)
            if isId(word) { continue }
            word = word.replacingOccurrences(of: uuidPattern, with: "", options: .regularExpression)
            guard !word.isEmpty else { continue }
            words.append(word)
        }
        while let first = words.first, isSeparator(first) { words.removeFirst() }
        while let last = words.last, isSeparator(last) { words.removeLast() }
        return words.joined(separator: " ")
    }

    /// The last words of a session as its row says them (a Stop's last sentence, a StopFailure's
    /// error): cut before the first `{` or `[`, so an API error's JSON body and its request id never
    /// show (« API Error: 529 »), the separator left before it dropped, without ids. The finished and
    /// error views keep the whole text.
    static func end(_ text: String) -> String {
        let head = text.firstIndex(where: { $0 == "{" || $0 == "[" }).map { String(text[..<$0]) } ?? text
        var line = clean(head)
        while let last = line.last, " :·-–|,;=".contains(last) { line.removeLast() }
        return line
    }

    /// Raw JSON: an object or a list, whole.
    static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, let last = trimmed.last else { return false }
        return (first == "{" && last == "}") || (first == "[" && last == "]")
    }

    private static let uuidPattern = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
    private static let edgePunctuation = CharacterSet(charactersIn: "()[]{}<>«»\"'`,;:.!?")

    /// A word made only of marks that join two pieces (« · », « : », « - », « | »): left alone at an
    /// end once an id went, it goes too. « ? », « ! » and « … » end a sentence and stay.
    private static func isSeparator(_ word: String) -> Bool {
        word.allSatisfy { "·•-–|/:,;=".contains($0) }
    }

    // MARK: - Pieces of an action

    /// « <verb> <file name> », or `fallback` when the path has no name left (none, « / », an id).
    private static func fileAction(_ verb: String, _ path: Any?, fallback: String) -> String {
        guard let path = path as? String, let name = fileName(path) else { return fallback }
        return verb + " " + name
    }

    /// The last component of a path, without ids; nil when nothing is left.
    private static func fileName(_ path: String) -> String? {
        guard let last = path.split(separator: "/").last(where: { !$0.isEmpty }) else { return nil }
        let name = clean(String(last))
        return name.isEmpty ? nil : name
    }

    /// An argument (a pattern, a query, a description) on one line, without ids, cut on a word at
    /// `argumentLimit`. Nil when it is not text, blank, or raw JSON.
    private static func argument(_ raw: Any?) -> String? {
        guard let text = raw as? String, !looksLikeJSON(text) else { return nil }
        let line = clean(text)
        return line.isEmpty ? nil : cut(line, limit: argumentLimit)
    }

    /// `text` cut to `limit` characters on a word, « … » attached to the last word kept; a first word
    /// longer than that is cut inside.
    static func cut(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let room = String(text.prefix(limit - 1))
        // The room ends where a word ends: it is kept whole.
        if text[text.index(text.startIndex, offsetBy: limit - 1)] == " " {
            return room.trimmingCharacters(in: .whitespaces) + "…"
        }
        if let space = room.lastIndex(of: " "), room.distance(from: room.startIndex, to: space) > 0 {
            return String(room[..<space]).trimmingCharacters(in: .whitespaces) + "…"
        }
        return room + "…"
    }

    /// The command of a Bash call as the row shows it: its first line; the part after the `cd` that
    /// open a chain (`&&`, `||`, `;`); without the variables set before it; a path by its last
    /// component; no id; stopped at raw JSON; then its first word and as many arguments as fit in
    /// `commandLimit`, cut on a word.
    private static func shortCommand(_ command: String) -> String? {
        guard let firstLine = command.split(whereSeparator: \.isNewline)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        var segments = String(firstLine)
            .replacingOccurrences(of: "&&", with: ";")
            .replacingOccurrences(of: "||", with: ";")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // The cd that only move to the project: the command after them is what runs.
        while segments.count > 1, segments[0].split(separator: " ").first == "cd" { segments.removeFirst() }
        guard let segment = segments.first else { return nil }
        var words = segment.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = words.first, first.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) != nil {
            words.removeFirst()
        }
        var shown: [String] = []
        var stoppedEarly = false
        for word in words {
            if word.contains("{") || word.contains("}") { stoppedEarly = true; break }
            if isId(word) { continue }
            var piece = word.replacingOccurrences(of: uuidPattern, with: "", options: .regularExpression)
            if shown.isEmpty || piece.hasPrefix("/") || piece.hasPrefix("~/") || piece.hasPrefix("./")
                || piece.hasPrefix("../") {
                if piece.contains("/"), let name = piece.split(separator: "/").last(where: { !$0.isEmpty }) {
                    piece = String(name)
                }
            }
            guard !piece.isEmpty else { continue }
            shown.append(piece)
        }
        guard !shown.isEmpty else { return nil }
        let line = shown.joined(separator: " ")
        if line.count > commandLimit { return cut(line, limit: commandLimit) }
        if stoppedEarly { return line + "…" }
        return line
    }

    /// The host of a URL without « www. », nil when there is none.
    private static func webHost(_ raw: Any?) -> String? {
        guard let text = raw as? String, let host = URL(string: text.trimmingCharacters(in: .whitespaces))?.host,
              !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - MCP tools

    /// `mcp__<server>__<tool>`: a verb from the tool's first word, else from its last (`issue_read`,
    /// GitHub's `<object>_<verb>`), its object in words (in French when known), and the server's
    /// name, « Liste les issues (Linear) », « Lit l'issue (GitHub) »; a bare verb « Lit dans Notion »;
    /// no known verb, « Utilise <words> (<server>) ». The server's own name in the tool goes
    /// (`notion-search`, `query_granola_meetings`). A server known by an id is not named. Nil for a
    /// name that is not an MCP tool's.
    private static func mcpAction(_ tool: String) -> String? {
        guard tool.hasPrefix("mcp__") else { return nil }
        let parts = tool.dropFirst(5).components(separatedBy: "__")
        guard parts.count >= 2 else {
            let name = clean(parts.joined())
            return name.isEmpty ? "Utilise un outil" : "Utilise " + name
        }
        let server = parts[0]
        let label = serverName(server)
        let serverWords = Set(words(of: server).filter { $0 != "claude" && $0 != "ai" && $0 != "plugin" })
        var toolWords = words(of: parts.dropFirst().joined(separator: "_"))
        toolWords.removeAll { serverWords.contains($0) || isId($0) }
        guard let first = toolWords.first, let last = toolWords.last else {
            return label.map { "Utilise " + $0 } ?? "Utilise un outil"
        }
        let verb: Verb
        let object: [String]
        if let leading = verbs[first] {
            verb = leading
            object = Array(toolWords.dropFirst())
        } else if let trailing = verbs[last] {
            verb = trailing
            object = Array(toolWords.dropLast())
        } else {
            let text = "Utilise " + toolWords.joined(separator: " ")
            return label.map { "\(text) (\($0))" } ?? text
        }
        if object.isEmpty {
            guard let label else { return verb.text }
            return "\(verb.text) dans \(label)"
        }
        let text = verb.text + " " + phrase(object, indefinite: verb.creates)
        return label.map { "\(text) (\($0))" } ?? text
    }

    /// A server's name as the user knows it: without `claude_ai_` (a claude.ai connector), the last
    /// part of a plugin's server (`plugin_<plugin>_<server>`), words capitalized, brands with their
    /// own capitals. Nil for a server known by an id, or none.
    static func serverName(_ server: String) -> String? {
        var name = server
        if name.lowercased().hasPrefix("claude_ai_") { name = String(name.dropFirst("claude_ai_".count)) }
        if name.lowercased().hasPrefix("plugin_"), let last = name.split(separator: "_").last {
            name = String(last)
        }
        guard !name.isEmpty, !isId(name) else { return nil }
        let parts = name.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " }).map { word -> String in
            if let brand = brands[word.lowercased()] { return brand }
            return word.prefix(1).uppercased() + word.dropFirst()
        }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    /// Brands whose capitals a plain capitalization would lose.
    private static let brands: [String: String] = [
        "github": "GitHub", "gitlab": "GitLab", "hubspot": "HubSpot", "linkedin": "LinkedIn",
    ]

    /// The words of a tool's or a server's name, in lower case: split on `_`, `-` and spaces, and
    /// between a lower case letter and a capital (`getWidgetStatus`).
    private static func words(of name: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previousLower = false
        for character in name {
            if character == "_" || character == "-" || character == " " {
                if !current.isEmpty { result.append(current.lowercased()) }
                current = ""
                previousLower = false
                continue
            }
            if character.isUppercase && previousLower, !current.isEmpty {
                result.append(current.lowercased())
                current = ""
            }
            current.append(character)
            previousLower = character.isLowercase
        }
        if !current.isEmpty { result.append(current.lowercased()) }
        return result
    }

    /// What a tool's first (or last) word does. `creates`: the object is a new one (« un brouillon »).
    private struct Verb {
        let text: String
        var creates = false
    }

    private static let verbs: [String: Verb] = [
        "list": Verb(text: "Liste"),
        "get": Verb(text: "Lit"), "read": Verb(text: "Lit"), "fetch": Verb(text: "Lit"),
        "create": Verb(text: "Crée", creates: true), "save": Verb(text: "Crée", creates: true),
        "update": Verb(text: "Met à jour"),
        "delete": Verb(text: "Supprime"),
        "search": Verb(text: "Cherche"), "query": Verb(text: "Cherche"), "find": Verb(text: "Cherche"),
        "send": Verb(text: "Envoie"),
        "add": Verb(text: "Ajoute"),
        "edit": Verb(text: "Modifie"), "write": Verb(text: "Modifie"),
    ]

    /// A noun the island says in French: singular, plural, feminine, and whether « le » or « la »
    /// becomes « l' ».
    private struct Noun {
        let singular: String
        let plural: String
        var feminine = false
        var elides = false
    }

    /// The objects MCP tools name most, in English singular.
    private static let nouns: [String: Noun] = [
        "issue": Noun(singular: "issue", plural: "issues", feminine: true, elides: true),
        "page": Noun(singular: "page", plural: "pages", feminine: true),
        "comment": Noun(singular: "commentaire", plural: "commentaires"),
        "message": Noun(singular: "message", plural: "messages"),
        "file": Noun(singular: "fichier", plural: "fichiers"),
        "event": Noun(singular: "événement", plural: "événements", elides: true),
        "draft": Noun(singular: "brouillon", plural: "brouillons"),
        "document": Noun(singular: "document", plural: "documents"),
        "doc": Noun(singular: "document", plural: "documents"),
        "project": Noun(singular: "projet", plural: "projets"),
        "channel": Noun(singular: "canal", plural: "canaux"),
        "email": Noun(singular: "email", plural: "emails", elides: true),
        "mail": Noun(singular: "email", plural: "emails", elides: true),
        "thread": Noun(singular: "fil", plural: "fils"),
        "label": Noun(singular: "libellé", plural: "libellés"),
        "user": Noun(singular: "utilisateur", plural: "utilisateurs", elides: true),
        "team": Noun(singular: "équipe", plural: "équipes", feminine: true, elides: true),
        "task": Noun(singular: "tâche", plural: "tâches", feminine: true),
        "meeting": Noun(singular: "réunion", plural: "réunions", feminine: true),
        "calendar": Noun(singular: "agenda", plural: "agendas", elides: true),
        "repository": Noun(singular: "dépôt", plural: "dépôts"),
        "repo": Noun(singular: "dépôt", plural: "dépôts"),
        "branch": Noun(singular: "branche", plural: "branches", feminine: true),
        "commit": Noun(singular: "commit", plural: "commits"),
        "pull request": Noun(singular: "pull request", plural: "pull requests", feminine: true),
        "pr": Noun(singular: "pull request", plural: "pull requests", feminine: true),
        "database": Noun(singular: "base de données", plural: "bases de données", feminine: true),
        "record": Noun(singular: "enregistrement", plural: "enregistrements", elides: true),
        "contact": Noun(singular: "contact", plural: "contacts"),
        "note": Noun(singular: "note", plural: "notes", feminine: true),
        "folder": Noun(singular: "dossier", plural: "dossiers"),
        "transcript": Noun(singular: "transcription", plural: "transcriptions", feminine: true),
        "account": Noun(singular: "compte", plural: "comptes"),
    ]

    /// The object of an MCP tool in French: a known noun with its article (« les issues », « l'issue »,
    /// « un brouillon » after a verb that creates), an unknown plural word with « les », else its
    /// words as they are.
    private static func phrase(_ words: [String], indefinite: Bool) -> String {
        let joined = words.joined(separator: " ")
        if let (noun, plural) = lookUp(joined) {
            if plural { return (indefinite ? "des " : "les ") + noun.plural }
            if indefinite { return (noun.feminine ? "une " : "un ") + noun.singular }
            if noun.elides { return "l'" + noun.singular }
            return (noun.feminine ? "la " : "le ") + noun.singular
        }
        if words.count == 1, let word = words.first, word.count > 3, word.hasSuffix("s"),
           !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is") {
            return (indefinite ? "des " : "les ") + word
        }
        return joined
    }

    /// A known noun for `phrase` (English, lower case), and whether it was plural.
    private static func lookUp(_ phrase: String) -> (Noun, Bool)? {
        if let noun = nouns[phrase] { return (noun, false) }
        if phrase.hasSuffix("ies"), let noun = nouns[String(phrase.dropLast(3)) + "y"] { return (noun, true) }
        if phrase.hasSuffix("es"), let noun = nouns[String(phrase.dropLast(2))] { return (noun, true) }
        if phrase.hasSuffix("s"), let noun = nouns[String(phrase.dropLast())] { return (noun, true) }
        return nil
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
