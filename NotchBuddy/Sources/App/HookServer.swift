import Foundation
import Darwin
import AppKit
import SwiftUI

// MARK: - HookServer
// Listens on a Unix domain socket for events from nb-hook (Claude Code hooks).
// Thread-safe: socket I/O on background threads, state updates dispatched to main queue.

final class HookServer: @unchecked Sendable {
    static let shared = HookServer()

    // Support directory paths
    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBuddy")
    }
    static var socketPath: String { supportDir.appendingPathComponent("nb.sock").path }
    static var hookScriptPath: String { supportDir.appendingPathComponent("nb-hook").path }

    private static let maxPayload = 1_048_576          // 1 MB — reject oversized messages
    private static let receiveTimeoutSeconds: Int = 5   // SO_RCVTIMEO on client sockets
    private static let maxConnections = 32              // concurrent connection ceiling

    private var serverFD: Int32 = -1
    private let connectionLock = NSLock()
    private var connectionCount = 0
    private var pendingApprovalFD: Int32 = -1         // held open while user decides
    private var approvalFDSource: (any DispatchSourceRead)? = nil  // monitors pendingApprovalFD
    private var pendingQuestionFD: Int32 = -1         // held open while user answers AskUserQuestion
    private var questionFDSource: (any DispatchSourceRead)? = nil  // monitors pendingQuestionFD
    /// One token per held request, next to its fd: the timeouts and the read sources act only on
    /// the request they were set up for (the next connection often reuses the fd number).
    private var requestTokens = RequestTokens()

    private var questionPillId: String = ""           // pill that owns the pending question
    private var questionSessionId: String? = nil      // session that owns the pending question
    private var focusBeforeQuestion: String? = nil    // saved focus to restore after question
    private var activeSessionId: String? = nil        // current Claude Code session
    private var focusBeforeApproval: String? = nil    // saved focus to restore after approval
    /// When each pill raised its binoculars (a search PreToolUse): PostToolUse leaves them up at
    /// least `SessionPhase.searchDwell`, by comparing dates (no timer).
    private var searchingSince: [String: Date] = [:]

    private init() {}

    // MARK: - Approval fd helpers

    @MainActor
    private func cancelApprovalFDSource() {
        approvalFDSource?.cancel()
        approvalFDSource = nil
    }

    /// Cancels the approval fd source (which closes the fd via its cancel handler), clears the
    /// approval, then shows the note for 3 s (`requestLeft`): the request still waiting replaces
    /// it, else the island folds.
    @MainActor
    private func dismissApprovalCard(note: String) {
        let onScreen = requestOnScreen
        // cancelApprovalFDSource() triggers the cancel handler which closes the fd.
        // Never close the fd here directly — Apple requires it to happen in the cancel handler.
        cancelApprovalFDSource()
        pendingApprovalFD = -1
        requestTokens.release(.approval)
        let state = AppState.shared
        let pillId = state.pendingApproval?.pillId ?? "integration_claude"
        let sessionId = state.pendingApproval?.sessionId
        state.pendingApproval = nil
        resumeSession(sessionId)
        requestLeft(.approval, pillId: pillId, onScreen: onScreen, note: note)
    }

    // MARK: - After a request leaves (spec §1: no request stays unseen)

    /// The request card the open island shows, nil when it is folded or shows another view.
    @MainActor
    private var requestOnScreen: PendingRequest? {
        let state = AppState.shared
        guard state.mode == .expanded else { return nil }
        if state.view == .approval, state.pendingApproval != nil { return .approval }
        if state.view == .question, state.pendingQuestion != nil { return .question }
        return nil
    }

    /// A permission or a question left (answered, handed back, handled elsewhere, timed out), its
    /// pending state already cleared. Its pill and the focus are given back, then the island shows
    /// what `PendingRequest.after` decides: the other request first, else the home; never a change
    /// under the pointer when the other card is the one on screen.
    @MainActor
    private func requestLeft(_ kind: PendingRequest, pillId: String, onScreen: PendingRequest?, note: String) {
        let state = AppState.shared
        let approval = state.pendingApproval != nil
        let question = state.pendingQuestion != nil
        // A request still waiting keeps the island pinned: Escape typed in another app never folds it.
        state.isPinned = approval || question
        // The pill goes back to work, unless the other request of the same pill still waits on it.
        if mayRemovePill(pillId) { state.updateTask(id: pillId, state: .working) }
        clearPillBadge(id: pillId)
        let after = PendingRequest.after(leaving: kind, onScreen: onScreen, note: !note.isEmpty,
                                         approval: approval, question: question)
        // The focus saved when this request took the screen.
        let saved: String?
        switch kind {
        case .approval: saved = focusBeforeApproval; focusBeforeApproval = nil
        case .question: saved = focusBeforeQuestion; focusBeforeQuestion = nil
        }
        if after == .keepView {
            // The other card stays, its pill in focus: it gives the oldest saved focus back when answered.
            switch kind {
            case .approval: focusBeforeQuestion = saved ?? focusBeforeQuestion
            case .question: focusBeforeApproval = saved ?? focusBeforeApproval
            }
        } else if let prev = saved, state.focusId == pillId, state.tasks.contains(where: { $0.id == prev }) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.focusId = prev }
        }
        switch after {
        case .keepView:        break
        case .note:            showNote(note)
        case .show(let next):  showHeldRequest(next)
        case .home:            state.view = state.tasks.isEmpty ? .empty : .overview
        }
    }

    /// Puts a request that waited behind another card (or behind a note) on screen: its pill takes
    /// the focus and the pose of the request, its badge goes. The card's buttons arm 0.6 s later.
    @MainActor
    private func showHeldRequest(_ kind: PendingRequest) {
        let state = AppState.shared
        let pillId: String
        switch kind {
        case .approval:
            guard let info = state.pendingApproval else { return }
            pillId = info.pillId
            if focusBeforeApproval == nil { focusBeforeApproval = state.focusId }
            state.updateTask(id: pillId, state: .approval)
        case .question:
            guard state.pendingQuestion != nil else { return }
            pillId = questionPillId
            if focusBeforeQuestion == nil { focusBeforeQuestion = state.focusId }
            state.updateTask(id: pillId, state: .question)
        }
        clearPillBadge(id: pillId)
        if state.focusId != pillId, state.tasks.contains(where: { $0.id == pillId }) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.focusId = pillId }
        }
        state.view = kind == .approval ? .approval : .question
    }

    /// Token of the note on screen: the 3 s timer of an earlier note never ends a later one.
    private var noteToken = 0

    /// Shows « Handled in … » or « Still waiting in … » for 3 s, then `PendingRequest.noteEnd`:
    /// the request still waiting replaces the note (the island stays open), else the island folds.
    /// Nothing happens if the note is no longer on screen.
    @MainActor
    private func showNote(_ note: String) {
        let state = AppState.shared
        noteToken += 1
        let token = noteToken
        state.noteMessage = note
        state.view = .note
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            let state = AppState.shared
            let end = PendingRequest.noteEnd(noteStillOnScreen: self.noteToken == token && state.view == .note,
                                             approval: state.pendingApproval != nil,
                                             question: state.pendingQuestion != nil)
            switch end {
            case .nothing:         break
            case .show(let next):  self.showHeldRequest(next)
            case .fold:            NotificationCenter.default.post(name: .islandCollapse, object: nil)
            }
        }
    }

    // MARK: - Question fd helpers

    @MainActor
    private func cancelQuestionFDSource() {
        questionFDSource?.cancel()
        questionFDSource = nil
    }

    /// Clears the question (its source closes the fd), then the island shows what `requestLeft`
    /// decides: the permission still waiting first, else the home.
    @MainActor
    private func dismissQuestionCard(note: String) {
        let onScreen = requestOnScreen
        cancelQuestionFDSource()
        pendingQuestionFD = -1
        requestTokens.release(.question)
        let state = AppState.shared
        let pillId = questionPillId
        resumeSession(questionSessionId)
        questionSessionId = nil
        state.pendingQuestion = nil
        requestLeft(.question, pillId: pillId, onScreen: onScreen, note: note)
    }

    /// Called by QuestionView. Sends answers JSON and cleans up.
    @MainActor
    func sendQuestionAnswers(_ answers: [String: Any]) {
        let fd = pendingQuestionFD
        pendingQuestionFD = -1
        let source = questionFDSource
        questionFDSource = nil
        if fd >= 0, let data = try? JSONSerialization.data(withJSONObject: ["permissionDecision": "answer", "answers": answers], options: .withoutEscapingSlashes),
           let json = String(data: data, encoding: .utf8) {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: json)
                DispatchQueue.main.async { source?.cancel() }
            }
            recordQuestionChoice(answers)
        } else {
            source?.cancel()
        }
        dismissQuestionCard(note: "")
    }

    /// Called by QuestionView "Reply in terminal" button (« Répondre dans Claude » for a question
    /// from the Claude desktop app). Answers "ask": the session asks the user itself.
    @MainActor
    func sendQuestionAsk() {
        let fd = pendingQuestionFD
        pendingQuestionFD = -1
        let source = questionFDSource
        questionFDSource = nil
        if fd >= 0 {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                DispatchQueue.main.async { source?.cancel() }
            }
        } else {
            source?.cancel()
        }
        dismissQuestionCard(note: "")
    }

    // MARK: - Choice history

    /// Keeps the question just answered in the history of choices (rules in ChoiceRecord).
    /// Called after the answer is handed to nb-hook, before the card is dismissed. A timeout,
    /// a displaced request, a card closed because the request was handled elsewhere and
    /// "Reply in terminal" never come here: no answer was given in the island.
    @MainActor
    private func recordQuestionChoice(_ answers: [String: Any]) {
        let state = AppState.shared
        guard let pending = state.pendingQuestion,
              let record = ChoiceRecord.question(pending.questions.map(\.question), answers: answers,
                                                 session: sessionTitle(questionSessionId, pillId: questionPillId),
                                                 date: Date())
        else { return }
        state.recordChoice(record)
    }

    /// The project name the island shows for a pill, "Session" when it is gone.
    @MainActor
    private func sessionName(for pillId: String) -> String {
        AppState.shared.tasks.first { $0.id == pillId }?.name ?? "Session"
    }

    /// The name of a request's session for the history: its roster row's title, whatever its
    /// shared pill is called now, else the pill's name.
    @MainActor
    private func sessionTitle(_ sessionId: String?, pillId: String) -> String {
        SessionRoster.title(of: sessionId, in: AppState.shared.sessions, fallback: sessionName(for: pillId))
    }

    /// Returns the tool_input serialized as sorted-keys JSON, "" if absent or empty.
    /// Same computation used in processPermissionRequest and processEvent to match PostToolUse.
    private static func approvalInputKey(_ input: [String: Any]) -> String {
        guard !input.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: input, options: .sortedKeys),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    // MARK: - Start

    func start() {
        // Ensure support directory exists (mode 0700 — not world-readable)
        let dir = Self.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700 as NSNumber], ofItemAtPath: dir.path)
        installHookScript()
        Thread.detachNewThread { self.serverThread() }
    }

    // MARK: - Socket server (background thread)

    private func serverThread() {
        let path = Self.socketPath
        // sun_path on macOS is 104 bytes including the NUL terminator → max 103 usable bytes
        let maxSunPathBytes = MemoryLayout<sockaddr_un>.size - MemoryLayout<sa_family_t>.size - 1
        guard path.utf8.count <= maxSunPathBytes else {
            NSLog("HookServer: socket path too long (\(path.utf8.count) bytes, max \(maxSunPathBytes)): \(path)")
            return
        }
        try? FileManager.default.removeItem(atPath: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cpath = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, c) in cpath.enumerated() where i < raw.count { raw[i] = UInt8(bitPattern: c) }
        }

        let bindRC = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindRC == 0 else { close(fd); return }
        // Restrict socket to owner only
        chmod(path, 0o600)
        guard Darwin.listen(fd, 32) == 0 else { close(fd); return }

        while true {
            let clientFD = Darwin.accept(fd, nil, nil)
            guard clientFD >= 0 else { break }
            // Reject connections from other users (same-UID check)
            var euid: uid_t = 0
            var egid: gid_t = 0
            guard getpeereid(clientFD, &euid, &egid) == 0, euid == getuid() else {
                close(clientFD)
                continue
            }
            // Enforce concurrent connection ceiling
            connectionLock.lock()
            let count = connectionCount
            if count < Self.maxConnections { connectionCount += 1 }
            connectionLock.unlock()
            guard count < Self.maxConnections else {
                close(clientFD)
                continue
            }
            Thread.detachNewThread { self.handleClient(fd: clientFD) }
        }
    }

    // MARK: - Client handler (background thread)

    private func handleClient(fd: Int32) {
        defer {
            connectionLock.lock(); connectionCount -= 1; connectionLock.unlock()
        }
        // 5-second receive timeout — unresponsive clients don't hold threads forever
        var tv = timeval(tv_sec: Self.receiveTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Read newline-delimited JSON
        var raw = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        outer: while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            for i in 0..<n {
                if buf[i] == UInt8(ascii: "\n") { break outer }
                raw.append(buf[i])
            }
            if raw.count > Self.maxPayload { break }
        }

        guard !raw.isEmpty,
              let payload = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
            return
        }

        let klayerKind = payload["klayer_kind"] as? String ?? ""

        // statusline payloads are handled separately — no session, no reveal, no sound
        if klayerKind == "statusline" {
            Task { @MainActor in self.processStatusLine(payload: payload) }
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
            return
        }

        // AskUserQuestion via --ask PreToolUse hook — hold fd open like PermissionRequest
        if klayerKind == "ask_user_question" {
            let toolInput = payload["tool_input"] as? [String: Any] ?? [:]
            if let parsed = AskQuestion.parse(toolInput: toolInput) {
                Task { @MainActor in self.processQuestionRequest(fd: fd, parsed: parsed, payload: payload) }
            } else {
                // Malformed payload — fall back: send ask so Claude Code re-asks in terminal
                sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }

        let eventName = payload["hook_event_name"] as? String ?? ""

        if eventName == "PermissionRequest" {
            // Hold fd open — Claude Code waits for our decision (up to 120s)
            Task { @MainActor in self.processPermissionRequest(fd: fd, payload: payload) }
        } else {
            Task { @MainActor in self.processEvent(name: eventName, payload: payload) }
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
        }
    }


    // MARK: - Event → AppState
    // Claude Code events route to the permanent "integration_claude" task.
    // Sessions from the Claude desktop app (klayer_agent "claude-desktop") route to the
    // dynamic "agent_claude-desktop" task. Any other klayer_agent is ignored.
    // A finished session opens the island on its end whether or not its pill has the focus, unless a
    // card waits or the user is using the island (FinishPresentation). Other view switches only happen
    // if the pill is focused. When not focused: state updates animate the mini bot in the pill; badge
    // shown for alerts.

    @MainActor
    private func processEvent(name: String, payload: [String: Any]) {
        let state = AppState.shared
        let sessionId = payload["session_id"] as? String ?? "unknown"
        let cwd = payload["cwd"] as? String ?? ""
        let rawName = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)

        // Determine which pill this event belongs to.
        // Only Claude Code (no klayer_agent) and the Claude desktop app ("claude-desktop") are
        // followed: a session from any other agent gets no pill.
        let rawAgent = payload["klayer_agent"] as? String ?? ""
        guard HookRouting.handledInIsland(agent: rawAgent) else {
            nbLog("Ignored \(name) from agent \(rawAgent.prefix(24)) (\(projectName))")
            return
        }
        let validAgent = validateAgent(rawAgent)

        let termProgram = payload["term_program"] as? String ?? ""
        let bundleId    = payload["bundle_id"]    as? String ?? ""
        let isEditorHost = Self.isEditorHost(termProgram: termProgram, bundleId: bundleId)

        // Routing:
        // • klayer_agent "claude-desktop" → the Claude desktop app pill (its permissions and questions get cards too)
        // • VS Code or Cursor → integration_claude
        // • a known terminal (Warp, Terminal, iTerm…) → integration_claude, host recorded on the task
        let agentId: String
        let isExternalAgent: Bool
        var hostApp: String? = nil
        if validAgent != nil {
            agentId = HookRouting.pillId(agent: rawAgent)
            isExternalAgent = true
        } else if isEditorHost {
            agentId = "integration_claude"
            isExternalAgent = false
        } else if let host = ClaudeHost.terminal(termProgram: termProgram, bundleId: bundleId) {
            agentId = "integration_claude"
            isExternalAgent = false
            hostApp = host.bundleId
        } else {
            nbLog("Ignored \(name) from \(termProgram.isEmpty ? bundleId : termProgram) (\(projectName))")
            return
        }
        // The app this session runs in, kept on its row: a click on the row and the finished
        // view's open button bring it forward, whatever the other sessions of the pill do.
        let sessionHost = SessionRoster.host(routed: hostApp, bundleId: bundleId)

        // While a permission request is pending, dismiss when the resolving event arrives,
        // then continue normal processing. Only skip normal processing when unresolved.
        if let pending = state.pendingApproval, agentId == pending.pillId {
            let handledNote = "Handled in \(requestHostName(forPill: pending.pillId))."
            var resolved = false
            switch name {
            case "PostToolUse", "PostToolUseFailure":
                // Only dismiss when this exact tool call finished — same session, tool and input.
                // Other parallel tools finishing must not close the card.
                if sessionId == pending.sessionId,
                   (payload["tool_name"] as? String ?? "") == pending.tool,
                   Self.approvalInputKey(payload["tool_input"] as? [String: Any] ?? [:]) == pending.inputKey {
                    dismissApprovalCard(note: handledNote)
                    resolved = true
                }
            case "Stop", "StopFailure", "UserPromptSubmit", "SessionEnd":
                // Turn ended — the permission is moot.
                if sessionId == pending.sessionId {
                    dismissApprovalCard(note: handledNote)
                    resolved = true
                }
            default: break
            }
            if !resolved {
                // Another session of the pill keeps its own row; the one that owns the card stays on "approval".
                if sessionId != pending.sessionId {
                    trackSession(event: name, payload: payload, sessionId: sessionId, pillId: agentId, title: projectName,
                                 host: sessionHost)
                }
                return
            }
            // Approval dismissed — fall through so the resolving event updates state normally.
        }

        // A question card of this pill waits for its answer. No event of ANOTHER session of the same
        // pill acts on it under the card (HookRouting.eventReachesPill), as under a permission card: it
        // is not put on working, finished or error, not renamed, and no view opens over the card. That
        // session's row is updated, and an end of turn badges the pill. (The session that owns the
        // question goes on below: its Stop only badges the pill while the card waits.)
        if !HookRouting.eventReachesPill(agentId, sessionId: sessionId,
                                         questionPill: state.pendingQuestion != nil ? questionPillId : nil,
                                         questionSession: questionSessionId) {
            trackSession(event: name, payload: payload, sessionId: sessionId, pillId: agentId, title: projectName,
                         host: sessionHost)
            if name == "Stop" || name == "StopFailure" {
                SoundEngine.shared.play(name == "Stop" ? "finish" : "error")
                setPillBadge(id: agentId, badge: name == "Stop" ? .finished : .error)
            }
            return
        }

        trackSession(event: name, payload: payload, sessionId: sessionId, pillId: agentId, title: projectName,
                     host: sessionHost)

        switch name {

        case "SessionStart":
            activeSessionId = sessionId
            if isExternalAgent { upsertExternalAgent(id: agentId, name: validAgent!) } else { upsertWorkspaceTask(id: agentId, projectName: projectName, hostApp: hostApp, bundleId: bundleId) }
            if let idx = state.tasks.firstIndex(where: { $0.id == agentId }) { state.tasks[idx].finalLine = nil }
            nbLog("SessionStart \(isExternalAgent ? agentId : projectName) (\(sessionId.prefix(8)))")
            if state.isPresent { expandIfNeeded(to: .overview) }
            SoundEngine.shared.play("work")

        case "UserPromptSubmit":
            activeSessionId = sessionId
            if isExternalAgent { upsertExternalAgent(id: agentId, name: validAgent!) } else { upsertWorkspaceTask(id: agentId, projectName: projectName, hostApp: hostApp, bundleId: bundleId) }
            if let idx = state.tasks.firstIndex(where: { $0.id == agentId }) { state.tasks[idx].finalLine = nil }
            state.updateTask(id: agentId, state: .thinking)
            if let prompt = payload["prompt"] as? String, !prompt.isEmpty {
                appendStep(id: agentId, step: String(prompt.prefix(60)))
            }
            // The finished view of this very session is stale now that it works again: it folds,
            // unless the pointer is on the island or the user clicked in it (state machine).
            if FinishPresentation.newPromptFoldsFinished(expanded: state.mode == .expanded,
                                                         view: state.view.rawValue,
                                                         finishedSessionId: state.finishedSession?.id,
                                                         promptSessionId: sessionId) {
                NotificationCenter.default.post(name: .finishedSessionMovedOn, object: nil)
            }
            if state.isPresent { expandIfNeeded(to: .overview) }

        case "PreToolUse":
            activeSessionId = sessionId
            let tool = payload["tool_name"] as? String ?? "Tool"
            if let idx = state.tasks.firstIndex(where: { $0.id == agentId }) { state.tasks[idx].finalLine = nil }
            // AskUserQuestion is handled via the dedicated --ask hook.
            // Skip state/step update here to avoid flickering over the question card.
            guard tool != "AskUserQuestion" else { break }
            if isExternalAgent { upsertExternalAgent(id: agentId, name: validAgent!) } else { upsertWorkspaceTask(id: agentId, projectName: projectName, hostApp: hostApp, bundleId: bundleId) }
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            // Grep, Glob, LS, WebSearch, WebFetch and a shell search raise the binoculars.
            if SessionPhase.of(tool: tool, input: input) == .searching {
                state.updateTask(id: agentId, state: .searching)
                searchingSince[agentId] = Date()
            } else {
                state.updateTask(id: agentId, state: .working)
                searchingSince[agentId] = nil
            }
            let step = localizedStep(tool: tool, input: input)
            appendStep(id: agentId, step: step)
            nbLog("PreToolUse \(tool)")

        case "PostToolUse":
            resumeWork(pillId: agentId)

        case "PostToolUseFailure":
            resumeWork(pillId: agentId)
            appendStep(id: agentId, step: "⚠ failed")

        case "Notification":
            let message = payload["message"] as? String ?? ""
            if Self.isRateLimit(message) {
                state.updateTask(id: agentId, state: .ratelimit)
                SoundEngine.shared.play("rate")
            } else if message.hasSuffix("?") {
                state.updateTask(id: agentId, state: .question)
                appendStep(id: agentId, step: message)
            }

        case "Stop":
            state.updateTask(id: agentId, state: .finished)
            let finalText = Self.finalText(of: payload)
            if !finalText.isEmpty {
                appendStep(id: agentId, step: finalText)
                if let idx = state.tasks.firstIndex(where: { $0.id == agentId }) {
                    state.tasks[idx].finalLine = finalText
                }
            }
            SoundEngine.shared.play("finish")
            // Claude finished a session: the island opens on its end (spec §4), unless a card waits or
            // the user is using the island (then the pill is only badged). Everything is read here, after
            // an approval card the Stop resolved was dismissed and gave the focus back.
            let presentation = FinishPresentation.decide(
                expanded: state.mode == .expanded, view: state.view.rawValue, pinned: state.isPinned,
                requestPending: state.pendingApproval != nil || state.pendingQuestion != nil)
            if presentation == .open, state.tasks.contains(where: { $0.id == agentId }) {
                // The finished view tells which session ended, whatever the pill and its focus become.
                var finished = state.sessions.first { $0.id == sessionId }
                    ?? SessionRow(id: sessionId, pillId: agentId, title: projectName, phase: .finished,
                                  lastAction: "", updatedAt: Date(), hostBundleId: sessionHost)
                if !finalText.isEmpty { finished.lastAction = finalText }
                state.finishedSession = finished
                if state.focusId != agentId {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.setFocus(agentId) }
                }
                expandIfNeeded(to: .finished)
            } else {
                setPillBadge(id: agentId, badge: .finished)
            }
            scheduleFinishCleanup(pillId: agentId, isExternalAgent: isExternalAgent)

        case "StopFailure":
            state.updateTask(id: agentId, state: .error)
            SoundEngine.shared.play("error")
            // Same rule as the end of a session: the error opens the island unless a card waits or the
            // user is using it (then the pill is only badged). Read now, after an approval card this
            // event resolved was dismissed and gave the focus back to another pill.
            let presentation = FinishPresentation.decide(
                expanded: state.mode == .expanded, view: state.view.rawValue, pinned: state.isPinned,
                requestPending: state.pendingApproval != nil || state.pendingQuestion != nil)
            if presentation == .open, state.tasks.contains(where: { $0.id == agentId }) {
                // The error view tells which session failed and why, like the finished view: its
                // project, the error text of the hook (none: the view says so), the app it runs in.
                var failed = state.sessions.first { $0.id == sessionId }
                    ?? SessionRow(id: sessionId, pillId: agentId, title: projectName, phase: .error,
                                  lastAction: "", updatedAt: Date(), hostBundleId: sessionHost)
                failed.lastAction = SessionRoster.failureText(of: payload) ?? ""
                state.failedSession = failed
                if state.focusId != agentId {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.setFocus(agentId) }
                }
                expandIfNeeded(to: .error)
            } else {
                setPillBadge(id: agentId, badge: .error)
            }

        case "SessionEnd":
            activeSessionId = nil
            if let idx = state.tasks.firstIndex(where: { $0.id == agentId }) { state.tasks[idx].finalLine = nil }
            // Another session of the Claude app shares this pill: keep it while a card waits on it,
            // it goes on its next event.
            if mayRemovePill(agentId) {
                state.removeTask(id: agentId)
            }

        case "SubagentStart":
            appendStep(id: agentId, step: "+ subagent")

        case "SubagentStop":
            appendStep(id: agentId, step: "• subagent done")

        default:
            break
        }
    }

    /// After a tool call the pill goes back to working, except that the binoculars of a search
    /// stay up `SessionPhase.searchDwell` at least: a 100 ms Grep must still be seen. Past that,
    /// the next event decides.
    @MainActor
    private func resumeWork(pillId: String) {
        let state = AppState.shared
        let searching = state.tasks.first { $0.id == pillId }?.state == .searching
        if searching, SessionPhase.postToolUseKeepsSearching(searchingSince: searchingSince[pillId], now: Date()) {
            return
        }
        searchingSince[pillId] = nil
        state.updateTask(id: pillId, state: .working)
    }

    // MARK: - Agent pill (Claude desktop app)

    /// VS Code and Cursor both host Claude Code in an integrated terminal.
    /// Cursor is identified solely by its stable Electron bundle ID: ToDesktop builds other
    /// apps too, so never match on "todesktop" alone.
    private static func isEditorHost(termProgram: String, bundleId: String) -> Bool {
        let bundle = bundleId.lowercased()
        return bundle == "com.todesktop.230313mzl4w4u92"
            || termProgram.lowercased().contains("vscode")
            || bundle.contains("vscode")
    }

    /// Creates the dynamic pill of a Claude desktop app session on first event, then no-ops.
    /// ID format: "agent_<name>" — never collides with "integration_*" pills.
    /// Inserted right after integration_claude so it appears in the visible prefix(4).
    @MainActor
    private func upsertExternalAgent(id: String, name: String) {
        let state = AppState.shared
        guard state.tasks.firstIndex(where: { $0.id == id }) == nil else { return }
        let color: String
        if let def = PillCatalog.definition(for: id) {
            color = def.color
        } else {
            color = IslandConst.colorForProject(name)
        }
        // The catalog's name (« Claude Desktop »), not the raw agent string « claude-desktop ».
        let task = AgentTask(id: id, name: PillCatalog.definition(for: id)?.name ?? name, color: color,
                             state: .idle, steps: [], source: .agent)
        if let claudeIdx = state.tasks.firstIndex(where: { $0.id == "integration_claude" }) {
            state.tasks.insert(task, at: claudeIdx + 1)
        } else {
            state.tasks.append(task)
        }
        if state.focusId == nil { state.focusId = id }
        state.syncMode()
    }

    // MARK: - Helpers

    @MainActor
    private func expandIfNeeded(to view: IslandView) {
        let state = AppState.shared
        let isAlert: Bool
        switch view {
        case .approval, .question, .finished, .error, .confused: isAlert = true
        default: isAlert = false
        }
        if state.mode == .expanded {
            // Approval and question always win; other alerts are blocked while one is pending.
            if view == .approval || view == .question {
                // Same path as on a closed island, so the state machine holds it open.
                NotificationCenter.default.post(name: .hookExpand, object: view)
            } else if isAlert && state.pendingApproval == nil && state.pendingQuestion == nil {
                if view == .finished || view == .error {
                    // The end of a session (FinishPresentation decided .open) takes the same path as
                    // on a closed island: the state machine then waits for a real hover then leave.
                    // Switched in place, an island opened by hovering the 220 pt home shrinks to
                    // 160 pt under a low pointer, which "leaves" it, and it folded unseen 0.6 s later.
                    NotificationCenter.default.post(name: .hookExpand, object: view)
                } else {
                    state.view = view
                }
            }
        } else if isAlert {
            // Alerts always force-expand
            NotificationCenter.default.post(name: .hookExpand, object: view)
        } else if state.mode == .hidden {
            // Non-alert work events: reveal compact only, never force-expand
            NotificationCenter.default.post(name: .hookReveal, object: nil)
        }
        // Already compact and non-alert: Klay state update is enough, no expand
    }

    // MARK: - Status line (plan gauge)

    @MainActor
    private func processStatusLine(payload: [String: Any]) {
        if let usage = ClaudePlanGauge.parse(payload: payload) {
            AppState.shared.claudePlanUsage = usage
        }
    }

    // MARK: - Permission request (blocking — Claude Code waits for decision)

    @MainActor
    private func processPermissionRequest(fd: Int32, payload: [String: Any]) {
        let state = AppState.shared
        let sessionId = payload["session_id"] as? String ?? "unknown"
        let cwd       = payload["cwd"]        as? String ?? ""
        let rawName   = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)

        let rawAgent = payload["klayer_agent"] as? String ?? ""
        let termProgram = payload["term_program"] as? String ?? ""
        let bundleId    = payload["bundle_id"]    as? String ?? ""

        // Claude Code and the Claude desktop app get an approval card; the pill that owns it is
        // the Claude Code pill or the Claude desktop pill. Any other request (another agent, a
        // terminal session with cards off in Settings) answers immediately with "ask" so that
        // tool re-asks in its own window.
        guard let route = Self.cardRoute(agent: rawAgent, termProgram: termProgram, bundleId: bundleId) else {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }
        let pillId = route.pillId
        let terminalHost = route.terminalHost

        let tool = payload["tool_name"] as? String ?? "Tool"
        let toolInput = payload["tool_input"] as? [String: Any] ?? [:]
        let inputKey = Self.approvalInputKey(toolInput)
        nbLog("PermissionRequest \(tool) [\(pillId)]")

        // AskUserQuestion is now handled via the dedicated --ask PreToolUse hook.
        // If it still arrives here as a PermissionRequest, reply "ask" so Claude Code
        // re-asks in the terminal — never show the question twice.
        if tool == "AskUserQuestion" {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }

        // What the card shows and the history records: the command, file, URL or argument (ApprovalSummary).
        let command = ApprovalSummary.text(tool: tool, input: toolInput, cwd: cwd)

        // A question card on screen is never swapped for this permission under the pointer: the
        // permission waits behind it, badged, and shows once the question is answered.
        let onScreen = requestOnScreen
        let takesScreen = PendingRequest.arrivalTakesScreen(.approval, onScreen: onScreen)
        let cardPill: String? = onScreen == .question ? questionPillId : nil

        if pendingApprovalFD >= 0 {
            // Displace the previous request: write "ask" then cancel its source.
            // The cancel handler closes the old fd — never close it directly.
            let old = pendingApprovalFD
            let oldSource = approvalFDSource
            approvalFDSource = nil
            // Its card is gone: that session goes back to working in the roster (it asks in its own window).
            resumeSession(state.pendingApproval?.sessionId)
            Task.detached { [weak self] in
                // "ask" → nb-hook outputs nothing → Claude Code re-asks
                self?.sendLine(fd: old, text: #"{"permissionDecision":"ask"}"#)
                DispatchQueue.main.async { oldSource?.cancel() }
            }
        }
        pendingApprovalFD = fd
        let token = requestTokens.hold(.approval)
        activeSessionId = sessionId

        upsertRequestPill(agent: rawAgent, pillId: pillId, projectName: projectName,
                          hostApp: terminalHost?.bundleId, bundleId: bundleId)
        // The pill of the question card on screen keeps the question's pose.
        if takesScreen || pillId != cardPill { state.updateTask(id: pillId, state: .approval) }
        state.updateSession(sessionId: sessionId, pillId: pillId, title: projectName, phase: .approval,
                            lastAction: SessionRoster.line(command),
                            hostBundleId: SessionRoster.host(routed: terminalHost?.bundleId, bundleId: bundleId))
        state.pendingApproval = ApprovalInfo(sessionId: sessionId, tool: tool,
                                              command: command, inputKey: inputKey, pillId: pillId,
                                              requestId: token)
        state.isPinned = true
        SoundEngine.shared.play("approval")

        if takesScreen {
            // Approval forces the island open — user must be able to respond.
            // Save current focus so we can restore it when the card is dismissed.
            if focusBeforeApproval == nil { focusBeforeApproval = state.focusId }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.focusId = pillId }
            expandIfNeeded(to: .approval)
        } else {
            // Badge and sound only; requestLeft shows it when the question leaves.
            setPillBadge(id: pillId, badge: .approval)
        }

        // Monitor fd: if the editor closes the connection (handled externally), dismiss the card.
        // The cancel handler closes the fd — never close it anywhere else.
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, self.requestTokens.isCurrent(token, .approval) else { return }
            self.dismissApprovalCard(note: "Handled in \(self.requestHostName(forPill: pillId)).")
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        approvalFDSource = source

        // Safety timeout — show a note and cancel without sending a decision.
        // nb-hook reads EOF from the cancel handler's close and exits; Claude Code re-asks.
        // Keyed by the request's token: a later request on the same fd number is not dismissed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 115) { [weak self] in
            guard let self, self.requestTokens.isCurrent(token, .approval) else { return }
            self.dismissApprovalCard(note: "Still waiting in \(self.requestHostName(forPill: pillId)).")
        }
    }

    /// Called by ApprovalView buttons. Writes the decision to the waiting nb-hook and cleans up.
    @MainActor
    func sendApprovalDecision(_ decision: String) {
        let onScreen = requestOnScreen
        let fd = pendingApprovalFD
        pendingApprovalFD = -1
        requestTokens.release(.approval)
        // Capture source before nulling — we send the decision first, then cancel the source.
        // The cancel handler closes the fd; never close it directly.
        let source = approvalFDSource
        approvalFDSource = nil

        let json: String
        switch decision {
        case "allow":  json = #"{"permissionDecision":"allow"}"#
        case "always": json = #"{"permissionDecision":"always"}"#
        case "ask":    json = #"{"permissionDecision":"ask"}"#
        default:       json = #"{"permissionDecision":"deny"}"#
        }

        if fd >= 0 {
            Task.detached { [weak self] in
                // Write decision while fd is still valid, then cancel source → cancel handler closes fd
                self?.sendLine(fd: fd, text: json)
                DispatchQueue.main.async { source?.cancel() }
            }
        } else {
            source?.cancel()
        }

        let state = AppState.shared
        let pillId = state.pendingApproval?.pillId ?? "integration_claude"
        // History: after the decision is handed to nb-hook, while the request is still in
        // pendingApproval (cleared just below). "ask" hands it back to the terminal: no record.
        if fd >= 0, let info = state.pendingApproval,
           let record = ChoiceRecord.permission(decision: decision,
                                                session: sessionTitle(info.sessionId, pillId: pillId),
                                                command: info.command, date: Date()) {
            state.recordChoice(record)
        }
        let answeredSessionId = state.pendingApproval?.sessionId
        state.pendingApproval = nil
        resumeSession(answeredSessionId)
        // The question still waiting shows next, else the home.
        requestLeft(.approval, pillId: pillId, onScreen: onScreen, note: "")
    }

    // MARK: - Question request

    @MainActor
    private func processQuestionRequest(fd: Int32, parsed: AskQuestion, payload: [String: Any]) {
        let state = AppState.shared
        let sessionId = payload["session_id"] as? String ?? "unknown"
        let cwd       = payload["cwd"]        as? String ?? ""
        let rawName   = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)

        let rawAgent    = payload["klayer_agent"] as? String ?? ""
        let termProgram = payload["term_program"]  as? String ?? ""
        let bundleId    = payload["bundle_id"]     as? String ?? ""
        // Same route as a permission: Claude Code and the Claude desktop app get a card, any
        // other request is answered "ask".
        guard let route = Self.cardRoute(agent: rawAgent, termProgram: termProgram, bundleId: bundleId) else {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }
        let pillId = route.pillId
        let terminalHost = route.terminalHost

        // A permission card on screen is never swapped for this question under the pointer: the
        // question waits behind it, badged, and shows once the permission is answered.
        let onScreen = requestOnScreen
        let takesScreen = PendingRequest.arrivalTakesScreen(.question, onScreen: onScreen)
        let cardPill: String? = onScreen == .approval ? state.pendingApproval?.pillId : nil

        // Displace any previous question waiting for an answer.
        if pendingQuestionFD >= 0 {
            let old = pendingQuestionFD
            let oldSrc = questionFDSource
            questionFDSource = nil
            // Its card is gone: that session goes back to working in the roster (it asks in its own window).
            resumeSession(questionSessionId)
            Task.detached { [weak self] in
                self?.sendLine(fd: old, text: #"{"permissionDecision":"ask"}"#)
                DispatchQueue.main.async { oldSrc?.cancel() }
            }
        }
        pendingQuestionFD = fd
        let token = requestTokens.hold(.question)
        activeSessionId = sessionId
        questionPillId = pillId
        questionSessionId = sessionId

        upsertRequestPill(agent: rawAgent, pillId: pillId, projectName: projectName,
                          hostApp: terminalHost?.bundleId, bundleId: bundleId)
        // The pill of the permission card on screen keeps the permission's pose.
        if takesScreen || pillId != cardPill { state.updateTask(id: pillId, state: .question) }
        state.updateSession(sessionId: sessionId, pillId: pillId, title: projectName, phase: .question,
                            lastAction: parsed.questions.first.flatMap { SessionRoster.line($0.question) },
                            hostBundleId: SessionRoster.host(routed: terminalHost?.bundleId, bundleId: bundleId))
        // The request id first: the card keys its draft and the arming of its buttons on it.
        state.pendingQuestionRequestId = token
        state.pendingQuestion = parsed
        state.isPinned = true
        SoundEngine.shared.play("approval")

        if takesScreen {
            if focusBeforeQuestion == nil { focusBeforeQuestion = state.focusId }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.focusId = pillId }
            expandIfNeeded(to: .question)
        } else {
            // Badge and sound only; requestLeft shows it when the permission leaves.
            setPillBadge(id: pillId, badge: .approval)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, self.requestTokens.isCurrent(token, .question) else { return }
            self.dismissQuestionCard(note: "")
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        questionFDSource = source

        // Keyed by the request's token: a later question on the same fd number is not dismissed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self, self.requestTokens.isCurrent(token, .question) else { return }
            // Send "ask" so nb-hook exits cleanly; Claude Code re-asks in terminal.
            let askFD = self.pendingQuestionFD
            self.pendingQuestionFD = -1
            let src = self.questionFDSource
            self.questionFDSource = nil
            Task.detached { [weak self] in
                self?.sendLine(fd: askFD, text: #"{"permissionDecision":"ask"}"#)
                DispatchQueue.main.async { src?.cancel() }
            }
            self.dismissQuestionCard(note: "")
        }
    }

    /// "Warp", "Terminal"… where the Claude Code pill's current session runs ("Claude Code" for an editor).
    @MainActor
    private var claudeHostName: String {
        ClaudeHost.name(for: AppState.shared.tasks.first { $0.id == "integration_claude" }?.hostApp)
    }

    /// False while a card of this pill waits for an answer (see `HookRouting.mayRemovePill`).
    @MainActor
    private func mayRemovePill(_ pillId: String) -> Bool {
        HookRouting.mayRemovePill(pillId,
                                  pendingApprovalPill: AppState.shared.pendingApproval?.pillId,
                                  pendingQuestionPill: pendingQuestionFD >= 0 ? questionPillId : nil)
    }

    /// Creates or updates the pill that owns a permission or question card. A request can be the
    /// first event seen of a Claude app session (the app started mid-session): the desktop pill is
    /// then made like the one SessionStart makes, before taking the project name the card shows.
    @MainActor
    private func upsertRequestPill(agent: String, pillId: String, projectName: String,
                                   hostApp: String?, bundleId: String) {
        if let desktopAgent = validateAgent(agent) { upsertExternalAgent(id: pillId, name: desktopAgent) }
        upsertWorkspaceTask(id: pillId, projectName: projectName, hostApp: hostApp, bundleId: bundleId)
    }

    /// Where the user answers a request of this pill, for the notes "Handled in …" and
    /// "Still waiting in …": "Claude" for the Claude desktop app, the host of the Claude Code
    /// session otherwise.
    @MainActor
    private func requestHostName(forPill pillId: String) -> String {
        pillId == HookRouting.desktopPillId ? "Claude" : claudeHostName
    }

    /// The pill that owns the pending question, so QuestionView can word its header link
    /// (the user answers in the Claude app, not in a terminal, for the desktop pill).
    @MainActor
    var pendingQuestionPillId: String { questionPillId }

    /// Where a permission or a question from Claude shows in the island: the pill that owns it
    /// and the terminal hosting the session. Nil when the island does not answer it and the
    /// caller replies "ask": an agent Klayer Island does not follow, or a terminal session while
    /// terminal cards are off in Settings. The Claude desktop app is its own host: it skips the
    /// editor and terminal gate and has no terminal host.
    private static func cardRoute(agent: String, termProgram: String, bundleId: String)
        -> (pillId: String, terminalHost: ClaudeHost?)? {
        guard HookRouting.handledInIsland(agent: agent) else { return nil }
        let pillId = HookRouting.pillId(agent: agent)
        if validateAgent(agent) != nil { return (pillId: pillId, terminalHost: nil) }
        if isEditorHost(termProgram: termProgram, bundleId: bundleId) { return (pillId: pillId, terminalHost: nil) }
        // Terminal sessions: only when turned on in Settings, else the terminal asks itself.
        guard let terminal = ClaudeHost.terminal(termProgram: termProgram, bundleId: bundleId),
              ClaudeHost.terminalCardsEnabled else { return nil }
        return (pillId: pillId, terminalHost: terminal)
    }

    /// Updates or transiently creates the Claude Code workspace pill task.
    /// If the task already exists (persistent), just updates its name and host.
    /// If missing (transient), creates it and inserts after the main pill.
    @MainActor
    private func upsertWorkspaceTask(id: String, projectName: String, hostApp: String? = nil, bundleId: String = "") {
        let state = AppState.shared
        if let idx = state.tasks.firstIndex(where: { $0.id == id }) {
            state.tasks[idx].name = projectName
            if id == "integration_claude" { state.tasks[idx].hostApp = hostApp }
            if !bundleId.isEmpty { state.tasks[idx].sessionBundleId = bundleId }
            return
        }
        // Transient: create and insert after the main pill
        let def = PillCatalog.definition(for: id)
        let color = def?.color ?? "#C0C4CC"
        let source = def?.source ?? .agent
        var task = AgentTask(id: id, name: projectName, color: color,
                             state: .idle, steps: [], source: source, isIntegration: true)
        if id == "integration_claude" { task.hostApp = hostApp }
        if !bundleId.isEmpty { task.sessionBundleId = bundleId }
        if let mainIdx = state.tasks.firstIndex(where: { $0.id == state.mainPillId }) {
            state.tasks.insert(task, at: mainIdx + 1)
        } else {
            state.tasks.insert(task, at: 0)
        }
        if state.focusId == nil { state.focusId = id }
        state.syncMode()
    }

    // MARK: - Badge helpers

    @MainActor
    private func setPillBadge(id: String, badge: PillBadge) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = badge
    }

    @MainActor
    private func clearPillBadge(id: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = nil
    }

    @MainActor
    private func appendStep(id: String, step: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].steps.append(step)
        if state.tasks[idx].steps.count > 20 { state.tasks[idx].steps.removeFirst() }
        state.tasks[idx].stepIndex = state.tasks[idx].steps.count - 1
    }

    // MARK: - After a Stop

    /// 5.2 s after a Stop: the Claude Code pill goes back to idle, the Claude app pill goes away
    /// (`HookRouting.stopCleanup`). Neither happens under a card of that pill that came in since the
    /// Stop, nor once the pill has moved on to another turn (checked from the first tick). The app
    /// pill stays while the open finished view still shows its session (the view reads that
    /// session, but the focus, the Klay and the buttons follow the pill), and goes once the view is
    /// left: the check repeats every 5.2 s, and only while that view is open.
    @MainActor
    private func scheduleFinishCleanup(pillId: String, isExternalAgent: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) {
            let state = AppState.shared
            let cleanup = HookRouting.stopCleanup(
                removesPill: isExternalAgent, cardWaits: !self.mayRemovePill(pillId),
                showingFinished: self.isShowingFinished(of: pillId),
                stillFinished: state.tasks.first(where: { $0.id == pillId })?.state == .finished)
            switch cleanup {
            case .keep:
                break
            case .again:
                self.scheduleFinishCleanup(pillId: pillId, isExternalAgent: isExternalAgent)
            case .idle:
                state.updateTask(id: pillId, state: .idle)
                self.clearPillBadge(id: pillId)
            case .remove:
                state.removeTask(id: pillId)
            }
        }
    }

    /// True while the island is open on the finished view of a session of this pill.
    @MainActor
    private func isShowingFinished(of pillId: String) -> Bool {
        let state = AppState.shared
        return state.mode == .expanded && state.view == .finished && state.finishedSession?.pillId == pillId
    }

    // MARK: - Session roster

    /// Feeds the roster of running sessions (one row per session) from a hook event, titled with the
    /// project folder name, with the app the session runs in (`host`, nil keeps the known one).
    /// Events that say nothing new about a session (PostToolUse, SubagentStart…) leave its row
    /// alone. Permissions and questions feed it from their own request.
    @MainActor
    private func trackSession(event name: String, payload: [String: Any], sessionId: String,
                              pillId: String, title: String, host: String?) {
        let phase: SessionPhase
        var action: String? = nil
        switch name {
        case "SessionStart":
            phase = .idle
            action = "Session démarrée"
        case "UserPromptSubmit":
            phase = .thinking
            if let prompt = payload["prompt"] as? String { action = SessionRoster.line(String(prompt.prefix(60))) }
        case "PreToolUse":
            let tool = payload["tool_name"] as? String ?? "Tool"
            // AskUserQuestion has its own card: processQuestionRequest puts the row on "question".
            guard tool != "AskUserQuestion" else { return }
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            phase = SessionPhase.of(tool: tool, input: input)   // « Cherche » for a search
            action = SessionRoster.line(localizedStep(tool: tool, input: input))
        case "Notification":
            guard Self.isRateLimit(payload["message"] as? String ?? "") else { return }
            phase = .ratelimit
        case "Stop":
            phase = .finished
            action = SessionRoster.line(Self.finalText(of: payload))
        case "StopFailure":
            phase = .error
            action = SessionRoster.failureText(of: payload)
        case "SessionEnd":
            AppState.shared.endSession(sessionId)
            return
        default:
            return
        }
        AppState.shared.updateSession(sessionId: sessionId, pillId: pillId, title: title,
                                      phase: phase, lastAction: action, hostBundleId: host)
    }

    /// The card of a session was answered or closed: its row leaves "approval" or "question" and goes
    /// back to "working", like its pill. A row that moved on since (finished, failed) stays as it is.
    @MainActor
    private func resumeSession(_ sessionId: String?) {
        let state = AppState.shared
        guard let sessionId,
              let row = state.sessions.first(where: { $0.id == sessionId }),
              row.phase == .approval || row.phase == .question else { return }
        state.updateSession(sessionId: sessionId, pillId: row.pillId, title: row.title,
                            phase: .working, lastAction: nil)
    }

    /// One line of the last assistant message of a Stop ("" when there is none).
    private static func finalText(of payload: [String: Any]) -> String {
        let raw = (payload["last_assistant_message"] as? String) ?? (payload["message"] as? String) ?? ""
        return ChatMarkdown.toOneLine(raw)
    }

    /// A Notification that says the usage limit was reached.
    private static func isRateLimit(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("rate limit") || lower.contains("limite d")
    }

    // MARK: - Project name alias mapping

    private func aliasProjectName(_ name: String) -> String {
        let aliases: [String: String] = [
            "notch-buddy":  "Notch Buddy",
            "notchbuddy":   "Notch Buddy",
            "notch_buddy":  "Notch Buddy",
        ]
        return aliases[name.lowercased()] ?? name
    }

    // MARK: - Localized step labels

    private func localizedStep(tool: String, input: [String: Any]) -> String {
        let labels: [String: String] = [
            "Bash":         String(localized: "step.runs",       defaultValue: "Runs"),
            "Read":         String(localized: "step.reads",      defaultValue: "Reads"),
            "Write":        String(localized: "step.writes",     defaultValue: "Writes"),
            "Edit":         String(localized: "step.edits",      defaultValue: "Edits"),
            "Glob":         String(localized: "step.searches",   defaultValue: "Searches"),
            "Grep":         String(localized: "step.searches",   defaultValue: "Searches"),
            "WebSearch":    String(localized: "step.web-search", defaultValue: "Searches the web"),
            "WebFetch":     String(localized: "step.fetches",    defaultValue: "Fetches"),
            "TodoWrite":    String(localized: "step.tasks",      defaultValue: "Tasks"),
            "Task":         String(localized: "step.agent",      defaultValue: "Agent"),
            "LS":           String(localized: "step.lists",      defaultValue: "Lists"),
            "MultiEdit":    String(localized: "step.edits",      defaultValue: "Edits"),
            "NotebookEdit": String(localized: "step.notebook",   defaultValue: "Notebook"),
        ]
        var label = labels[tool] ?? tool

        // MCP tools arrive as mcp__server__tool — show "server · tool"
        if tool.hasPrefix("mcp__") {
            let rest = String(tool.dropFirst(5))
            let parts = rest.components(separatedBy: "__")
            label = parts.count >= 2 ? "\(parts[0]) · \(parts.dropFirst().joined(separator: "__"))" : rest
        }

        // Bash: infer a more precise verb from the command
        if tool == "Bash", let cmd = input["command"] as? String {
            return "\(bashVerb(cmd)) · \(oneLine(cmd))"
        }

        if let cmd = input["command"] as? String {
            return "\(label) · \(oneLine(cmd))"
        } else if let path = input["path"] as? String {
            return "\(label) · \(URL(fileURLWithPath: path).lastPathComponent)"
        } else if let file = input["file_path"] as? String {
            return "\(label) · \(URL(fileURLWithPath: file).lastPathComponent)"
        } else if let query = input["query"] as? String {
            return "\(label) · \(oneLine(query))"
        }
        return label
    }

    /// The localized verb of a shell command (`BashVerb`, the same rule as the search pose).
    private func bashVerb(_ command: String) -> String {
        switch BashVerb.of(command) {
        case .reads:    return String(localized: "step.reads",    defaultValue: "Reads")
        case .searches: return String(localized: "step.searches", defaultValue: "Searches")
        case .tests:    return String(localized: "step.tests",    defaultValue: "Tests")
        case .runs:     return String(localized: "step.runs",     defaultValue: "Runs")
        }
    }

    /// Collapses whitespace so a multi-line command stays one line of its session row.
    private func oneLine(_ text: String, limit: Int = 60) -> String {
        let collapsed = text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
                            .joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    // MARK: - Logging

    private func nbLog(_ message: String) {
        appendAppLog("nb.log", message)
    }

    private func sendLine(fd: Int32, text: String) {
        let bytes = Array((text + "\n").utf8)
        bytes.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let n = Darwin.send(fd, buffer.baseAddress! + sent, buffer.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    // MARK: - nb-hook script installation

    func installHookScript() {
        let dir = Self.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700 as NSNumber], ofItemAtPath: dir.path)
        // nb-hook: shell wrapper (always exits 0, calls nb-hook.py via python3)
        let wrapperURL = URL(fileURLWithPath: Self.hookScriptPath)
        try? nbHookShellWrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: wrapperURL.path)
        // nb-hook.py: Python relay
        let pyURL = wrapperURL.deletingLastPathComponent().appendingPathComponent("nb-hook.py")
        try? nbHookPython.write(to: pyURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: pyURL.path)
    }

    // MARK: - Outdated hook detection

    /// Returns true if settings.json has a Klayer Island hook that needs updating:
    /// either a PermissionRequest hook with timeout < 120s, or the AskUserQuestion
    /// PreToolUse matcher is missing (requires Claude Code 2.1.85+).
    static func hooksNeedUpdate() -> Bool {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any] else {
            return false
        }
        // Track whether any Klayer Island hook is installed at all
        var hasKlayerIslandHooks = false

        if let permReqHooks = hooks["PermissionRequest"] as? [[String: Any]] {
            for matcher in permReqHooks {
                if let hookList = matcher["hooks"] as? [[String: Any]] {
                    for hook in hookList {
                        if let cmd = hook["command"] as? String,
                           cmd.contains("NotchBuddy") || cmd.contains("klayer") {
                            hasKlayerIslandHooks = true
                            if let timeout = hook["timeout"] as? Int, timeout < 120 { return true }
                        }
                    }
                }
            }
        }

        // Check that the AskUserQuestion PreToolUse entry exists
        if hasKlayerIslandHooks {
            let preToolHooks = hooks["PreToolUse"] as? [[String: Any]] ?? []
            let hasAskEntry = preToolHooks.contains { m in
                (m["matcher"] as? String) == "AskUserQuestion"
                && (m["hooks"] as? [[String: Any]])?.contains {
                    let cmd = $0["command"] as? String ?? ""
                    return cmd.contains("NotchBuddy") || cmd.contains("klayer")
                } ?? false
            }
            if !hasAskEntry { return true }
        }
        return false
    }

    // MARK: - Claude Code settings.json hook installer

    private var _pendingHooksData: Data?
    /// The bytes of settings.json the pending preview was computed from.
    private var _pendingHooksOriginal: Data?

    /// Returns preview JSON without writing — call writeClaudeHooks() to confirm.
    func previewClaudeHooks() throws -> String {
        let (data, original) = try buildHooksData()
        _pendingHooksData = data
        _pendingHooksOriginal = original
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Writes the hooks to disk (call after user confirms preview).
    /// Refused if settings.json changed since the preview, or cannot be backed up.
    func writeClaudeHooks() throws {
        guard let data = _pendingHooksData else { return }
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        try ClaudeSettingsFile.write(data, to: settingsURL, expecting: _pendingHooksOriginal)
        _pendingHooksData = nil
        _pendingHooksOriginal = nil
    }

    private func buildHooksData() throws -> (data: Data, original: Data?) {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        // Unreadable or invalid settings must stop here, never count as empty.
        let snapshot = try ClaudeSettingsFile.read(at: settingsURL)
        var settings = snapshot.object
        let hookPath = Self.hookScriptPath
        let quotedCmd = "\"\(hookPath.replacingOccurrences(of: "\"", with: "\\\""))\""
        let events: [(String, Int)] = [
            ("SessionStart", 10), ("SessionEnd", 10),
            ("UserPromptSubmit", 10),
            ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
            ("PermissionRequest", 120),
            ("Notification", 10),
            ("Stop", 10), ("StopFailure", 10),
            ("SubagentStart", 10), ("SubagentStop", 10),
        ]
        // "hooks" in a shape we do not know is refused, never replaced.
        var hooks = try ClaudeSettingsFile.hooks(in: settings, name: "settings.json")
        for (event, timeout) in events {
            var existing = try ClaudeSettingsFile.hookGroups(in: hooks, event: event, name: "settings.json")
            existing.removeAll { ($0["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains("NotchBuddy") == true || ($0["command"] as? String)?.contains("klayer") == true } ?? false }
            existing.append(["hooks": [["type": "command", "command": quotedCmd, "timeout": timeout]]])
            hooks[event] = existing
        }
        // Dedicated AskUserQuestion PreToolUse hook (Claude Code 2.1.85+, timeout 130s)
        var preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []
        preToolUse.append([
            "matcher": "AskUserQuestion",
            "hooks": [["type": "command", "command": "\(quotedCmd) --ask", "timeout": 130]],
        ])
        hooks["PreToolUse"] = preToolUse
        settings["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        return (data, snapshot.bytes)
    }

    func uninstallClaudeHooks() throws {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        let snapshot = try ClaudeSettingsFile.read(at: settingsURL)
        var settings = snapshot.object
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for key in hooks.keys {
            if var matchers = hooks[key] as? [[String: Any]] {
                matchers.removeAll { matcher in
                    (matcher["hooks"] as? [[String: Any]])?.contains {
                        ($0["command"] as? String)?.contains("NotchBuddy") == true ||
                        ($0["command"] as? String)?.contains("klayer") == true
                    } ?? false
                }
                if matchers.isEmpty { hooks.removeValue(forKey: key) }
                else { hooks[key] = matchers }
            }
        }
        settings["hooks"] = hooks
        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try ClaudeSettingsFile.write(newData, to: settingsURL, expecting: snapshot.bytes)
    }

    // MARK: - Claude plan status line installer

    private var statusLinePreviousURL: URL {
        Self.supportDir.appendingPathComponent("statusline-previous.json")
    }

    /// Returns true if our statusLine command is installed in ~/.claude/settings.json.
    static func statusLineInstalled() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sl = settings["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String else { return false }
        return cmd.contains("nb-hook")
    }

    private var _pendingStatusLineData: Data?
    /// The bytes of settings.json the pending preview was computed from.
    private var _pendingStatusLineOriginal: Data?
    private var _pendingPreviousData: Data?
    private var _pendingDeletePrevious: Bool = false

    /// Returns a diff string (only the statusLine key: before → after) without writing anything.
    func previewStatusLine(install: Bool) throws -> String {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        // Unreadable or invalid settings must stop here, never count as empty.
        let snapshot = try ClaudeSettingsFile.read(at: settingsURL)
        let settings = snapshot.object
        let hookPath = Self.hookScriptPath
        let quotedPath = hookPath.replacingOccurrences(of: "\"", with: "\\\"")
        let quotedCmd = "\"\(quotedPath)\" --statusline"

        // Reset pending side-effects
        _pendingPreviousData = nil
        _pendingDeletePrevious = false

        let oldSL = settings["statusLine"] as? [String: Any]
        let newSL: [String: Any]?

        if install {
            // Check that Python 3 is available (requires Command Line Tools)
            let clCheck = Process()
            clCheck.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
            clCheck.arguments = ["-p"]
            clCheck.standardOutput = FileHandle.nullDevice
            clCheck.standardError = FileHandle.nullDevice
            try? clCheck.run()
            clCheck.waitUntilExit()
            if clCheck.terminationStatus != 0 {
                throw NSError(domain: "Klayer Island", code: 1,
                              userInfo: [NSLocalizedDescriptionKey:
                                  "Command Line Tools are required but not installed. Run: xcode-select --install"])
            }

            if let existing = oldSL,
               let cmd = existing["command"] as? String, !cmd.contains("nb-hook") {
                // Keep existing object but swap command; save old for later restoration
                var updated = existing
                updated["command"] = quotedCmd
                newSL = updated
                _pendingPreviousData = try? JSONSerialization.data(withJSONObject: existing,
                                                                   options: [.prettyPrinted, .sortedKeys])
            } else if let existing = oldSL,
                      let cmd = existing["command"] as? String, cmd.contains("nb-hook") {
                // Already installed — rebuild to update path if needed, keep other fields
                var updated = existing
                updated["command"] = quotedCmd
                newSL = updated
            } else {
                newSL = ["type": "command", "command": quotedCmd]
            }
        } else {
            // Uninstall: only if it's ours
            if let cur = oldSL, let cmd = cur["command"] as? String, cmd.contains("nb-hook") {
                if let prevData = try? Data(contentsOf: statusLinePreviousURL),
                   let prevObj = (try? JSONSerialization.jsonObject(with: prevData)) as? [String: Any] {
                    newSL = prevObj
                    _pendingDeletePrevious = true
                } else {
                    newSL = nil
                }
            } else {
                newSL = oldSL  // not ours — leave unchanged
            }
        }

        // Build the full settings.json with the new statusLine
        var newSettings = settings
        if let sl = newSL {
            newSettings["statusLine"] = sl
        } else {
            newSettings.removeValue(forKey: "statusLine")
        }
        let data = try JSONSerialization.data(withJSONObject: newSettings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        _pendingStatusLineData = data
        _pendingStatusLineOriginal = snapshot.bytes

        // Build a compact diff: show only the statusLine key before → after
        func slJSON(_ val: [String: Any]?) throws -> String {
            guard let v = val else { return "(none)" }
            let d = try JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted, .sortedKeys])
            return String(data: d, encoding: .utf8) ?? "(none)"
        }
        let before = try slJSON(oldSL)
        let after  = try slJSON(newSL)
        return "statusLine\nBefore:\n\(before)\n\nAfter:\n\(after)"
    }

    /// Writes settings.json and commits side effects (call after user confirms).
    func writeStatusLine() throws {
        guard let data = _pendingStatusLineData else { return }
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        try ClaudeSettingsFile.write(data, to: settingsURL, expecting: _pendingStatusLineOriginal)
        // Commit side effects only after successful write
        if let prevData = _pendingPreviousData {
            try? prevData.write(to: statusLinePreviousURL, options: .atomic)
        }
        if _pendingDeletePrevious {
            try? FileManager.default.removeItem(at: statusLinePreviousURL)
        }
        _pendingStatusLineData = nil
        _pendingStatusLineOriginal = nil
        _pendingPreviousData = nil
        _pendingDeletePrevious = false
    }

    // MARK: - Claude Code installed-state detection

    /// True when ~/.claude/settings.json already routes Claude Code events to Klayer Island,
    /// for every Claude Code session, whatever editor or terminal runs it.
    static func claudeHooksInstalled() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return false }
        return klayerHooksPresent(inSettings: json)
    }
}

// MARK: - Notification names for hook server → controller communication

extension Notification.Name {
    static let hookExpand = Notification.Name("notchBuddy.hookExpand")
}

// MARK: - nb-hook shell wrapper
// Invoked by Claude Code via /bin/sh or directly via shebang.
// Always exits 0 — never blocks Claude Code.
// Checks xcode-select before running python3 to avoid triggering the
// "install developer tools" dialog on machines without Xcode CLI tools.

private let nbHookShellWrapper = """
#!/bin/sh
# Klayer Island hook relay — always exits 0, never blocks Claude Code
HOOK_DIR="$(dirname "$0")"
out=""
if xcode-select -p >/dev/null 2>&1; then
    out=$(/usr/bin/python3 "$HOOK_DIR/nb-hook.py" "$@" 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
        out=""
    fi
fi
if [ -n "$out" ]; then
    printf '%s\\n' "$out"
fi
exit 0
"""

// MARK: - nb-hook Python relay

private let nbHookPython = """
#!/usr/bin/env python3
# nb-hook.py — Klayer Island hook relay for Claude Code
# Reads JSON from stdin, forwards to Klayer Island via Unix socket, translates response.
import sys, json, os, socket

def main():
    raw = b''
    payload = {}
    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            if '--statusline' not in sys.argv[1:]:
                return
        else:
            payload = json.loads(raw)
    except Exception:
        if '--statusline' not in sys.argv[1:]:
            return

    socket_path = os.path.expanduser(
        '~/Library/Application Support/NotchBuddy/nb.sock'
    )

    # --statusline mode: relay rate_limits to Klayer Island, then delegate to saved previous
    if '--statusline' in sys.argv[1:]:
        relay = {
            'klayer_kind': 'statusline',
            'session_id': payload.get('session_id', ''),
            'rate_limits': payload.get('rate_limits', {}),
        }
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.3)
            s.connect(socket_path)
            s.sendall((json.dumps(relay) + '\\n').encode())
            s.close()
        except Exception:
            pass
        prev_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'statusline-previous.json')
        if os.path.exists(prev_file):
            try:
                import subprocess
                with open(prev_file) as f:
                    prev = json.load(f)
                cmd = prev.get('command', '')
                if cmd:
                    result = subprocess.run(['/bin/sh', '-c', cmd], input=raw,
                                             capture_output=True, timeout=10)
                    if result.stdout:
                        sys.stdout.buffer.write(result.stdout)
                        sys.stdout.buffer.flush()
            except Exception:
                pass
        return

    # --ask mode: dedicated hook for AskUserQuestion via PreToolUse (Claude Code 2.1.85+)
    if '--ask' in sys.argv[1:]:
        tool = payload.get('tool_name', '')
        if tool != 'AskUserQuestion':
            return  # Not an AskUserQuestion invocation — exit cleanly (no output)
        payload['klayer_kind'] = 'ask_user_question'
        # A question from a Claude desktop app session (Code tab) carries this entrypoint: tag it
        # like the other events so the island shows the question instead of answering "ask".
        if not payload.get('klayer_agent') and os.environ.get('CLAUDE_CODE_ENTRYPOINT') == 'claude-desktop':
            payload['klayer_agent'] = 'claude-desktop'
        env = os.environ
        payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
        payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
        payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
        payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
        if 'cwd' not in payload or not payload['cwd']:
            payload['cwd'] = os.getcwd()
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(125)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision == 'answer':
                    answers = resp_obj.get('answers', {})
                    questions = payload.get('tool_input', {}).get('questions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'allow', 'updatedInput': {'questions': questions, 'answers': answers}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → Claude Code asks in terminal
        except Exception:
            pass
        return

    # Claude Code sends no klayer_agent. A hook that an earlier Klayer Island wired for another
    # tool still passes --agent <name>: tag the payload with it so the app ignores that tool
    # (no pill, permission answered "ask") instead of reading it as a Claude Code session.
    args = sys.argv[1:]
    agent = ''
    i = 0
    while i < len(args):
        if args[i] == '--agent' and i + 1 < len(args):
            agent = args[i + 1]
            i += 2
        else:
            i += 1
    if agent:
        payload.setdefault('klayer_agent', agent)
    # Claude Code sessions from the Claude desktop app (Code tab) report this entrypoint;
    # route them to the Claude Desktop pill instead of dropping them (no VS Code terminal).
    if not payload.get('klayer_agent') and os.environ.get('CLAUDE_CODE_ENTRYPOINT') == 'claude-desktop':
        payload['klayer_agent'] = 'claude-desktop'

    # Enrich with terminal context
    env = os.environ
    payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
    payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
    payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
    payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
    if 'cwd' not in payload or not payload['cwd']:
        payload['cwd'] = os.getcwd()

    event = payload.get('hook_event_name', '')
    # socket_path is already defined above

    if event == 'PermissionRequest':
        # Block and wait for Klayer Island's decision (Claude Code allows up to 120s)
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(118)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision in ('allow', 'always'):
                    if decision == 'always':
                        # Let Claude Code persist the rule via updatedPermissions
                        suggestions = payload.get('permission_suggestions', [])
                        out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedPermissions': suggestions}}}
                    else:
                        out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'deny':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'deny', 'message': 'Denied from Klayer Island'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'answer':
                    # AskUserQuestion answered from the notch
                    answers = resp_obj.get('answers', {})
                    questions = payload.get('tool_input', {}).get('questions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedInput': {'questions': questions, 'answers': answers}}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → Claude Code re-asks
        except Exception:
            pass
        # App unreachable, timed out, or no explicit decision — print nothing: Claude Code asks itself
        sys.exit(0)

    # All other events: fire-and-forget (0.3s timeout, never blocks)
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(socket_path)
        s.sendall((json.dumps(payload) + '\\n').encode())
        s.close()
    except Exception:
        pass  # Always exit cleanly — never block Claude Code

try:
    main()
except Exception:
    pass
sys.exit(0)
"""
