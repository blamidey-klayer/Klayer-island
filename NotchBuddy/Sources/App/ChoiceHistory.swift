import Foundation

/// One request from Claude answered from the island: a permission (Allow, Deny, Always) or an
/// AskUserQuestion. `session` is the project name shown on the island, `prompt` what Claude
/// asked (the command, or the questions), `answer` what the user chose.
struct ChoiceRecord: Codable, Equatable {
    enum Kind: String, Codable {
        case permission
        case question
    }

    let date: Date
    let session: String
    let kind: Kind
    let prompt: String
    let answer: String
}

// MARK: - What the island records

extension ChoiceRecord {
    /// A permission answered from the island: « Autorisé », « Refusé » or « Toujours ».
    /// "ask" hands the request back to the terminal, so nothing was answered and there is no
    /// record. Any other decision is a refusal, as HookServer sends it to the hook.
    static func permission(decision: String, session: String, command: String, date: Date) -> ChoiceRecord? {
        let answer: String
        switch decision {
        case "allow":  answer = "Autorisé"
        case "always": answer = "Toujours"
        case "ask":    return nil
        default:       answer = "Refusé"
        }
        return ChoiceRecord(date: date, session: session, kind: .permission, prompt: command, answer: answer)
    }

    /// A question answered from the island. `questions` are the question texts in the order
    /// asked, `answers` is what the card sends back: a label (single select) or an array of
    /// labels (multi select) under each question text. The record holds the questions joined
    /// by " / " and every chosen label, in question order, joined by ", ". No label, no record.
    static func question(_ questions: [String], answers: [String: Any], session: String, date: Date) -> ChoiceRecord? {
        let labels = questions.flatMap { question -> [String] in
            switch answers[question] {
            case let one as String:    return [one]
            case let many as [String]: return many
            default:                   return []
            }
        }
        guard !labels.isEmpty else { return nil }
        return ChoiceRecord(date: date, session: session, kind: .question,
                            prompt: questions.joined(separator: " / "),
                            answer: labels.joined(separator: ", "))
    }
}

// MARK: - What the open island shows

extension ChoiceRecord {
    /// One row of the last choices on the open island (spec §6): the time as "HH:mm", the
    /// session, the prompt on one line and the answer.
    struct Row: Equatable {
        /// Longest answer on a row, ellipsis included: the answer is shown whole next to the
        /// prompt, so several options chosen at once must not push the prompt out.
        static let answerLimit = 20

        let time: String
        let session: String
        let prompt: String
        let answer: String

        /// "HH:mm · session · prompt", the parts that are not empty: the view shows it on one
        /// line and cuts its end, the prompt, when the row is too narrow.
        var summary: String {
            [time, session, prompt].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// The row of this choice, its time read in `timeZone` on 24 hours. Line breaks and tabs of
    /// the prompt become one space and its ends are trimmed, the prompt is not cut (the view
    /// does it); an answer longer than 20 characters is cut to 19 followed by « … ».
    func row(in timeZone: TimeZone = .current) -> Row {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let oneLine = prompt.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let shortAnswer = answer.count > Row.answerLimit
            ? String(answer.prefix(Row.answerLimit - 1)) + "…"
            : answer
        return Row(time: time, session: session, prompt: oneLine, answer: shortAnswer)
    }
}

/// The last 20 choices the user made from the island, newest first, kept in a local JSON file
/// so they survive a restart. Nothing leaves the Mac: no network, no logging of the prompts.
/// A missing or damaged file loads as empty and the next `record` writes a valid one again.
/// Foundation only, tested by scripts/test-choice-history.sh. Single-threaded by design:
/// AppState (main actor) owns the instance.
final class ChoiceHistory {
    /// How many choices are kept; the oldest one drops when a new one arrives.
    static let limit = 20
    /// Longest stored prompt, ellipsis included: a long heredoc or a command carrying a token
    /// is not kept whole.
    static let promptLimit = 300

    private let fileURL: URL
    /// Newest first, at most `limit`.
    private(set) var records: [ChoiceRecord]

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.records = Self.load(from: fileURL)
    }

    /// Adds `r` as the newest choice (its prompt cut to `promptLimit` characters with "…"),
    /// drops what exceeds the limit and rewrites the file.
    func record(_ r: ChoiceRecord) {
        var kept = r
        if r.prompt.count > Self.promptLimit {
            kept = ChoiceRecord(date: r.date, session: r.session, kind: r.kind,
                                prompt: String(r.prompt.prefix(Self.promptLimit - 1)) + "…",
                                answer: r.answer)
        }
        records.insert(kept, at: 0)
        if records.count > Self.limit { records.removeLast(records.count - Self.limit) }
        save()
    }

    /// The `n` newest choices, newest first.
    func latest(_ n: Int) -> [ChoiceRecord] {
        Array(records.prefix(max(0, n)))
    }

    // MARK: - File

    private static func load(from url: URL) -> [ChoiceRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode([ChoiceRecord].self, from: data) else { return [] }
        return Array(stored.prefix(limit))
    }

    /// Atomic write (the file is complete or untouched). A failure is silent: the history is a
    /// convenience, and the prompts it holds stay out of the logs.
    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        let folder = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700 as NSNumber])
        try? data.write(to: fileURL, options: .atomic)
    }
}
