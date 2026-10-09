#if KLAYER_E2E
import Foundation
import Darwin

// MARK: - End-to-end test commands (test build only)
// Compiled only into the test build of the macOS CI (`KLAYER_E2E`, see .github/workflows/build.yml),
// and answered only when that build was launched with KLAYER_ISLAND_TEST=1: tests/e2e/island_e2e.py
// reads the island and answers its cards through them. The shipped build has none of this (the CI
// checks its binary, then launches it and checks it answers none). A decision goes through what the
// card's buttons call, and only for the card on screen: nothing here decides on its own.

extension HookServer {
    /// What the test sends, read off the socket's thread into Sendable values.
    private enum E2ECommand: Sendable {
        case state
        case decide(String)
        /// Question text → the labels chosen (one for a single-select question). Nil when malformed.
        case answer([String: [String]]?)
        case shortcut(String)
        /// An app came to the front (its bundle id), as NSWorkspace would say (Task 27).
        case activate(String)
        case unknown(String)
    }

    /// The test commands, named in full in the reply to an unknown one (and found there by the CI's
    /// `strings` check of the test build, its control for the check of the shipped binary).
    private static let e2eCommandList = "e2e_state, e2e_decide, e2e_answer, e2e_shortcut or e2e_activate"

    /// Answers a test command on its connection with one JSON line, then closes it. False when `kind`
    /// is not a test command or the app was not launched by the test: the payload then goes on like
    /// any other event (and is ignored).
    func handleE2ECommand(kind: String, payload: [String: Any], fd: Int32) -> Bool {
        guard kind.hasPrefix("e2e_"),
              ClaudeAppWatchRules.isTestLaunch(environment: ProcessInfo.processInfo.environment) else { return false }
        let command: E2ECommand
        switch kind {
        case "e2e_state":    command = .state
        case "e2e_decide":   command = .decide(payload["decision"] as? String ?? "")
        case "e2e_answer":   command = .answer(Self.e2eSelections(payload["answers"]))
        case "e2e_shortcut": command = .shortcut(payload["action"] as? String ?? "")
        case "e2e_activate": command = .activate(payload["bundle_id"] as? String ?? "")
        default:             command = .unknown(kind)
        }
        Task { @MainActor in
            let reply = self.e2eReply(command)
            Task.detached {
                self.sendLine(fd: fd, text: reply)
                close(fd)
            }
        }
        return true
    }

    /// `{question: label}` or `{question: [labels]}` as the labels per question, nil when malformed.
    private static func e2eSelections(_ raw: Any?) -> [String: [String]]? {
        guard let raw = raw as? [String: Any] else { return nil }
        var selections: [String: [String]] = [:]
        for (question, value) in raw {
            switch value {
            case let one as String:    selections[question] = [one]
            case let many as [String]: selections[question] = many
            default:                   return nil
            }
        }
        return selections
    }

    @MainActor
    private func e2eReply(_ command: E2ECommand) -> String {
        let reply: [String: Any]
        switch command {
        case .state:                 reply = e2eState()
        case .decide(let decision):  reply = e2eDecide(decision)
        case .answer(let chosen):    reply = e2eAnswer(chosen)
        case .shortcut(let name):    reply = e2eShortcut(name)
        case .activate(let bundleId): reply = e2eActivate(bundleId)
        case .unknown(let kind):     reply = Self.e2eError("unknown test command \(kind): expected \(Self.e2eCommandList)")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys, .withoutEscapingSlashes]),
              let line = String(data: data, encoding: .utf8) else {
            return #"{"ok":false,"error":"reply not encodable"}"#
        }
        return line
    }

    private static func e2eError(_ message: String) -> [String: Any] {
        ["ok": false, "error": message]
    }

    /// The island as the test reads it: open or not, its view, the cards waiting, the finished
    /// session, the rows of the list, the note, and the choices the island recorded.
    @MainActor
    private func e2eState() -> [String: Any] {
        let state = AppState.shared
        let sessions: [[String: Any]] = state.sessions.map { row in
            let entrypoint: Any = row.entrypoint ?? NSNull()
            return ["id": row.id, "phase": row.phase.rawValue, "title": row.title, "pill": row.pillId,
                    "detail": row.detail, "entrypoint": entrypoint, "open": Self.e2eOpenTarget(row.openTarget)]
        }
        let choices: [[String: Any]] = state.recentChoices.map {
            ["kind": $0.kind.rawValue, "prompt": $0.prompt, "answer": $0.answer, "session": $0.session,
             "date": $0.date.timeIntervalSince1970]
        }
        var reply: [String: Any] = [
            "ok": true,
            "mode": state.mode.rawValue,
            "view": state.view.rawValue,
            "sessions": sessions,
            "choices": choices,
            "terminalCards": ClaudeHost.terminalCardsEnabled,
        ]
        if let approval = state.pendingApproval {
            reply["pendingApproval"] = ["pill": approval.pillId, "command": approval.command,
                                        "tool": approval.tool, "session": approval.sessionId]
        } else {
            reply["pendingApproval"] = NSNull()
        }
        if let question = state.pendingQuestion {
            let questions: [[String: Any]] = question.questions.map {
                ["question": $0.question, "options": $0.options.map(\.label), "multiSelect": $0.multiSelect]
            }
            reply["pendingQuestion"] = ["pill": pendingQuestionPillId, "questions": questions] as [String: Any]
        } else {
            reply["pendingQuestion"] = NSNull()
        }
        if let finished = state.finishedSession {
            reply["finishedSession"] = ["id": finished.id, "title": finished.title, "pill": finished.pillId]
        } else {
            reply["finishedSession"] = NSNull()
        }
        if let note = state.noteMessage {
            reply["note"] = note
        } else {
            reply["note"] = NSNull()
        }
        if let alert = state.claudeAppAlert {
            reply["claudeAppAlert"] = ["title": alert.title, "message": alert.message,
                                       "source": alert.source == .chat ? "chat" : "codeSession",
                                       "openLabel": alert.source.openLabel]
        } else {
            reply["claudeAppAlert"] = NSNull()
        }
        return reply
    }

    /// A click on a button of the permission card on screen: Deny, Allow or Always.
    @MainActor
    private func e2eDecide(_ decision: String) -> [String: Any] {
        guard ["allow", "deny", "always"].contains(decision) else {
            return Self.e2eError("decision must be allow, deny or always")
        }
        let state = AppState.shared
        guard state.mode == .expanded, state.view == .approval, state.pendingApproval != nil else {
            return Self.e2eError("no permission card on screen")
        }
        sendApprovalDecision(decision)
        return ["ok": true]
    }

    /// The question card on screen sent with these choices: the card's own selections, made into
    /// Claude Code's answers as its send does.
    @MainActor
    private func e2eAnswer(_ chosen: [String: [String]]?) -> [String: Any] {
        let state = AppState.shared
        guard state.mode == .expanded, state.view == .question, let pending = state.pendingQuestion else {
            return Self.e2eError("no question card on screen")
        }
        guard let chosen, Set(chosen.keys) == Set(pending.questions.map(\.question)) else {
            return Self.e2eError("answers must name each question asked, by its text")
        }
        var selections: [[String]] = []
        for item in pending.questions {
            let labels = chosen[item.question] ?? []
            guard !labels.isEmpty, !labels.contains(where: \.isEmpty), item.multiSelect || labels.count == 1 else {
                return Self.e2eError("one label for a single-select question, at least one for a multi-select one")
            }
            selections.append(labels)
        }
        sendQuestionAnswers(AskQuestion.buildAnswers(questions: pending.questions, selections: selections))
        return ["ok": true]
    }

    /// What a row opens, as the test reads it: `url:<link>`, `activate:<bundle id>`, or null.
    private static func e2eOpenTarget(_ target: OpenTarget?) -> Any {
        switch target {
        case .url(let url)?:           return "url:" + url.absoluteString
        case .activate(let bundleId)?: return "activate:" + bundleId
        case nil:                      return NSNull()
        }
    }

    /// An app came to the front: posted as the window controller's own activation input, so the
    /// card or note on screen steps aside exactly as when NSWorkspace says so (CardStepAside).
    @MainActor
    private func e2eActivate(_ bundleId: String) -> [String: Any] {
        guard !bundleId.isEmpty else { return Self.e2eError("bundle_id is required") }
        NotificationCenter.default.post(name: .appCameToFront, object: bundleId)
        return ["ok": true]
    }

    /// A keyboard shortcut pressed (`openChat` opens the chat), through the hot keys' own handler.
    @MainActor
    private func e2eShortcut(_ name: String) -> [String: Any] {
        guard let action = ShortcutAction(rawValue: name) else {
            return Self.e2eError("unknown shortcut \(name)")
        }
        HotKeyCenter.shared.performForTest(action)
        return ["ok": true]
    }
}
#endif
