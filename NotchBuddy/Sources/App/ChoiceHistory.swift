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

/// The last 20 choices the user made from the island, newest first, kept in a local JSON file
/// so they survive a restart. Nothing leaves the Mac: no network, no logging of the prompts.
/// A missing or damaged file loads as empty and the next `record` writes a valid one again.
/// Foundation only, tested by scripts/test-choice-history.sh. Single-threaded by design:
/// AppState (main actor) owns the instance.
final class ChoiceHistory {
    /// How many choices are kept; the oldest one drops when a new one arrives.
    static let limit = 20

    private let fileURL: URL
    /// Newest first, at most `limit`.
    private(set) var records: [ChoiceRecord]

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.records = Self.load(from: fileURL)
    }

    /// Adds `r` as the newest choice, drops what exceeds the limit and rewrites the file.
    func record(_ r: ChoiceRecord) {
        records.insert(r, at: 0)
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
