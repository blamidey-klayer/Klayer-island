import Foundation

/// The history of what Claude asked and what the user answered from the island: the last 20
/// answers, newest first, kept in a local JSON file that survives a restart and never crashes
/// the app when it is missing or damaged. Tests use a temporary folder, never the real
/// Application Support.
@main
enum ChoiceHistoryTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("keeps_20_newest_first", keeps20NewestFirst),
            ("latest_5", latest5),
            ("persists_round_trip", persistsRoundTrip),
            ("missing_or_corrupt_file_is_empty", missingOrCorruptFileIsEmpty),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Choice history: \(cases.count) cases passed")
    }

    /// Runs `body` with a fresh temporary folder, removed afterwards.
    static func withTempDir(_ body: (URL) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("klayer-choice-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        body(dir)
    }

    /// Whole seconds, because the file stores ISO 8601 dates without fractions.
    static func choice(_ n: Int) -> ChoiceRecord {
        ChoiceRecord(date: Date(timeIntervalSince1970: 1_700_000_000 + Double(n)),
                     session: "Projet \(n)",
                     kind: n.isMultiple(of: 2) ? .permission : .question,
                     prompt: "demande \(n)",
                     answer: n.isMultiple(of: 2) ? "Autorisé" : "Option A, Option B")
    }

    static func keeps20NewestFirst() {
        withTempDir { dir in
            let history = ChoiceHistory(fileURL: dir.appendingPathComponent("choices.json"))
            for n in 1...25 { history.record(choice(n)) }
            precondition(history.records.count == 20,
                         "the history keeps the 20 latest choices, got \(history.records.count)")
            precondition(history.records.first == choice(25), "the newest choice comes first")
            precondition(history.records.last == choice(6), "the 5 oldest are dropped")
        }
    }

    static func latest5() {
        withTempDir { dir in
            let history = ChoiceHistory(fileURL: dir.appendingPathComponent("choices.json"))
            precondition(history.latest(5).isEmpty, "an empty history has no latest choices")
            for n in 1...25 { history.record(choice(n)) }
            precondition(history.latest(5) == [choice(25), choice(24), choice(23), choice(22), choice(21)],
                         "latest(5) is the 5 newest, newest first")
            precondition(history.latest(0).isEmpty)
            precondition(history.latest(100).count == 20, "latest never returns more than is kept")
        }
    }

    static func persistsRoundTrip() {
        withTempDir { dir in
            // The folder does not exist yet: the first record creates it.
            let file = dir.appendingPathComponent("Support/choices.json")
            let history = ChoiceHistory(fileURL: file)
            for n in 1...3 { history.record(choice(n)) }
            let reopened = ChoiceHistory(fileURL: file)
            precondition(reopened.records == history.records,
                         "a new object on the same file reads the same records")
            precondition(reopened.records.map(\.kind) == [.question, .permission, .question],
                         "the kind survives the round trip")
            precondition(reopened.records.first == choice(3))
        }
    }

    static func missingOrCorruptFileIsEmpty() {
        withTempDir { dir in
            let file = dir.appendingPathComponent("choices.json")
            precondition(ChoiceHistory(fileURL: file).records.isEmpty, "a missing file loads as empty")

            try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try! Data("{oops".utf8).write(to: file)
            let history = ChoiceHistory(fileURL: file)
            precondition(history.records.isEmpty, "a corrupt file loads as empty, without crashing")

            history.record(choice(1))
            let reopened = ChoiceHistory(fileURL: file)
            precondition(reopened.records == [choice(1)],
                         "the next record rewrites a valid JSON file")
        }
    }
}
