import Foundation

/// The history of what Claude asked and what the user answered from the island: the last 20
/// answers, newest first, kept in a local JSON file that survives a restart and never crashes
/// the app when it is missing or damaged, the rules deciding what an answer records, and the
/// row the open island shows for a choice.
/// Tests use a temporary folder, never the real Application Support.
@main
enum ChoiceHistoryTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("keeps_20_newest_first", keeps20NewestFirst),
            ("latest_5", latest5),
            ("persists_round_trip", persistsRoundTrip),
            ("missing_or_corrupt_file_is_empty", missingOrCorruptFileIsEmpty),
            ("empty_or_wrong_shape_file_is_empty", emptyOrWrongShapeFileIsEmpty),
            ("file_with_more_than_20_records_loads_the_20_newest", fileWithMoreThan20RecordsLoadsThe20Newest),
            ("long_prompt_is_capped_at_300_characters", longPromptIsCapped),
            ("ask_records_nothing", askRecordsNothing),
            ("labels_for_each_decision", labelsForEachDecision),
            ("multi_select_is_flattened_in_question_order", multiSelectIsFlattenedInQuestionOrder),
            ("empty_answers_record_nothing", emptyAnswersRecordNothing),
            ("row_time_is_hh_mm_in_the_given_time_zone", rowTimeIsHHmmInTheGivenTimeZone),
            ("row_prompt_is_one_line_session_and_answer_kept", rowPromptIsOneLineSessionAndAnswerKept),
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

    static func emptyOrWrongShapeFileIsEmpty() {
        for (label, content) in [("an empty 0-byte", ""), ("a {} object", "{}"), ("a wrong-shape records", #"[{"x":1}]"#)] {
            withTempDir { dir in
                let file = dir.appendingPathComponent("choices.json")
                try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try! Data(content.utf8).write(to: file)
                let history = ChoiceHistory(fileURL: file)
                precondition(history.records.isEmpty, "\(label) file loads as empty, without crashing")
                history.record(choice(1))
                precondition(ChoiceHistory(fileURL: file).records == [choice(1)],
                             "the next record rewrites a valid file over \(label) file")
            }
        }
    }

    static func fileWithMoreThan20RecordsLoadsThe20Newest() {
        withTempDir { dir in
            let file = dir.appendingPathComponent("choices.json")
            try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            // 30 records, newest first, as the app writes them.
            try! encoder.encode((1...30).reversed().map(choice)).write(to: file)
            let history = ChoiceHistory(fileURL: file)
            precondition(history.records.count == 20, "load keeps 20 records, got \(history.records.count)")
            precondition(history.records.first == choice(30), "the newest stays first")
            precondition(history.records.last == choice(11), "the 10 oldest are dropped")
        }
    }

    static func longPromptIsCapped() {
        withTempDir { dir in
            let file = dir.appendingPathComponent("choices.json")
            let history = ChoiceHistory(fileURL: file)
            let exactly300 = String(repeating: "a", count: 300)
            let token = "export API_TOKEN=secret && " + String(repeating: "x", count: 1000)
            for prompt in [exactly300, token] {
                history.record(ChoiceRecord(date: choice(1).date, session: "Projet", kind: .permission,
                                            prompt: prompt, answer: "Autorisé"))
            }
            let reopened = ChoiceHistory(fileURL: file)
            precondition(reopened.records[1].prompt == exactly300, "300 characters are kept whole")
            let capped = reopened.records[0].prompt
            precondition(capped.count == 300, "a longer prompt is cut to 300 characters, got \(capped.count)")
            precondition(capped.hasSuffix("…"), "the cut ends with an ellipsis")
            precondition(capped.hasPrefix("export API_TOKEN=secret && "), "the start of the prompt is kept")
            precondition(!(try! String(contentsOf: file, encoding: .utf8)).contains(token),
                         "the whole prompt is not written to the file")
        }
    }

    // MARK: - What an answer records

    static let when = Date(timeIntervalSince1970: 1_700_000_000)

    static func askRecordsNothing() {
        precondition(ChoiceRecord.permission(decision: "ask", session: "Klayer", command: "npm test", date: when) == nil,
                     "\"ask\" hands the request back to the terminal: no answer, no record")
    }

    static func labelsForEachDecision() {
        for (decision, label) in [("allow", "Autorisé"), ("deny", "Refusé"), ("always", "Toujours")] {
            let r = ChoiceRecord.permission(decision: decision, session: "Klayer", command: "npm test", date: when)
            precondition(r == ChoiceRecord(date: when, session: "Klayer", kind: .permission,
                                           prompt: "npm test", answer: label),
                         "\(decision) records « \(label) » with the session and the command")
        }
    }

    static func multiSelectIsFlattenedInQuestionOrder() {
        let questions = ["Quel moteur ?", "Quels modules ?", "Autre chose ?"]
        // The dictionary has no order: the labels follow the questions, and a question
        // without answer is skipped.
        let answers: [String: Any] = ["Quels modules ?": ["Auth", "Facturation"], "Quel moteur ?": "Postgres"]
        let r = ChoiceRecord.question(questions, answers: answers, session: "Klayer", date: when)
        precondition(r == ChoiceRecord(date: when, session: "Klayer", kind: .question,
                                       prompt: "Quel moteur ? / Quels modules ? / Autre chose ?",
                                       answer: "Postgres, Auth, Facturation"),
                     "got \(String(describing: r))")
    }

    static func emptyAnswersRecordNothing() {
        let questions = ["Quel moteur ?"]
        precondition(ChoiceRecord.question(questions, answers: [:], session: "Klayer", date: when) == nil,
                     "no answers, no record")
        precondition(ChoiceRecord.question(questions, answers: ["Quel moteur ?": [String]()],
                                           session: "Klayer", date: when) == nil,
                     "a multi select with nothing chosen records nothing")
        precondition(ChoiceRecord.question(questions, answers: ["Une autre question": "Oui"],
                                           session: "Klayer", date: when) == nil,
                     "an answer to a question that was not asked records nothing")
    }

    // MARK: - Row of the open island

    static let utc = TimeZone(identifier: "UTC")!

    static func rowTimeIsHHmmInTheGivenTimeZone() {
        let r = ChoiceRecord(date: when, session: "Klayer", kind: .permission, prompt: "npm test", answer: "Autorisé")
        // 1_700_000_000 is 22:13:20 UTC, 23:13:20 in Paris (UTC+1 in November).
        precondition(r.row(in: utc).time == "22:13", "hours and minutes, no seconds, got \(r.row(in: utc).time)")
        let paris = r.row(in: TimeZone(identifier: "Europe/Paris")!).time
        precondition(paris == "23:13", "the time is read in the given zone, got \(paris)")

        // Zero padded on 24 hours: midnight and a morning time.
        let midnight = ChoiceRecord(date: Date(timeIntervalSince1970: 1_700_006_425), session: "Klayer",
                                    kind: .question, prompt: "Quel moteur ?", answer: "Postgres")
        precondition(midnight.row(in: utc).time == "00:00", "got \(midnight.row(in: utc).time)")
        let morning = ChoiceRecord(date: Date(timeIntervalSince1970: 1_800_000_000 + 65 * 60), session: "Klayer",
                                   kind: .question, prompt: "Quel moteur ?", answer: "Postgres")
        precondition(morning.row(in: utc).time == "09:05", "got \(morning.row(in: utc).time)")
    }

    static func rowPromptIsOneLineSessionAndAnswerKept() {
        let r = ChoiceRecord(date: when, session: "Projet A", kind: .permission,
                             prompt: "git add .\n\tgit commit -m \"fix\"\r\n\n  git push  ", answer: "Toujours")
        let row = r.row(in: utc)
        precondition(row.prompt == "git add . git commit -m \"fix\" git push",
                     "line breaks and tabs become one space and the ends are trimmed, got \(row.prompt)")
        precondition(row.session == "Projet A" && row.answer == "Toujours", "the session and the answer are kept")
        precondition(row == ChoiceRecord.Row(time: "22:13", session: "Projet A",
                                             prompt: "git add . git commit -m \"fix\" git push", answer: "Toujours"))

        let blank = ChoiceRecord(date: when, session: "Projet A", kind: .question, prompt: "", answer: "Oui")
        precondition(blank.row(in: utc).prompt.isEmpty, "an empty prompt stays empty")
        // The view cuts a long prompt itself (one line, truncated): the row keeps it whole.
        let long = String(repeating: "x", count: 300)
        let longRow = ChoiceRecord(date: when, session: "Projet A", kind: .permission, prompt: long, answer: "Refusé")
        precondition(longRow.row(in: utc).prompt == long, "the row does not cut the prompt")
    }
}
