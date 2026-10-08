import SwiftUI

// MARK: - Dispatch view content by IslandView

struct IslandViewContent: View {
    let view: IslandView
    @ObservedObject var state: AppState

    var body: some View {
        switch view {
        case .overview:  OverviewView(state: state)
        case .empty:     EmptyStateView(state: state)
        case .approval:  ApprovalView(state: state)
        case .question:  QuestionView(state: state)
        case .error:     ErrorView(state: state)
        case .finished:  FinishedView(state: state)
        case .confused:  ConfusedView()
        case .upload:    UploadView(state: state)
        case .uploading: UploadingView(state: state)
        case .choose:    ChooseView(state: state)
        case .mail:      MailView(state: state)
        case .prompt:    PromptView(state: state)
        case .searching: SearchingView(state: state)
        case .result:    ResultView(state: state)
        case .note:      NoteView(state: state)
        case .settings:  SettingsIslandView(state: state)
        case .greeting:  EmptyView()  // GreetingCanvasView overlaid in IslandRootView
        }
    }
}

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var state: AppState
    @State private var showingIntegrationDetail = false
    /// The Claude Code hooks are missing from ~/.claude/settings.json. Read when the home shows
    /// (`refreshHome`), never in `body`: it reads a file.
    @State private var hooksMissing = false

    var agent: AgentTask? { state.focusTask }

    /// Height of the cards drawn for the 160 pt island (GitHub, Spotify, plan detail), kept
    /// as a band centred in the 168 pt card of the home.
    static let legacyCardHeight: CGFloat = 98

    /// The home (conversations in progress, last choices) shows for the Claude pills and when no
    /// pill has the focus. GitHub and Spotify keep their own card (spec §6).
    private var showsHome: Bool {
        guard let id = agent?.id else { return true }
        return id == "integration_claude" || id == HookRouting.desktopPillId
    }

    var body: some View {
        HStack(spacing: 10) {
            // Left card: the home, or the card of the GitHub or Spotify pill with its ↗ button
            ZStack(alignment: .topLeading) {
                CardBackground(wash: nil)

                if showsHome {
                    homeContent
                } else {
                    // GitHub and Spotify cards are drawn for a 98 pt card: they sit, with their ↗
                    // button, in a 98 pt band centred in the taller home card, so they line up with
                    // Klay exactly as on the 160 pt island.
                    ZStack(alignment: .topLeading) {
                        if let agent = agent {
                            IntegrationCardView(task: agent, showingDetail: $showingIntegrationDetail)
                        }

                        // ↗ opens the service of the GitHub or Spotify pill: last in the band so it
                        // renders on top, hidden while any detail is open
                        if !showingIntegrationDetail && !state.showingPlanDetail {
                            Button(action: { openServiceTarget(agent) }) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(Color(hex: "#5F646D"))
                                    .frame(width: 16, height: 16)
                                    .background(Color.white.opacity(0.07))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                            .padding(.trailing, 10)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    // Top-leading in the band, as they sat in their 98 pt card: the content and the ↗
                    // button keep their place (↗ 8 pt below the band's top, 10 pt from the right)
                    .frame(height: Self.legacyCardHeight, alignment: .topLeading)
                    .frame(maxHeight: .infinity)
                }

                // Plan detail overlays on top of normal content (home view only), in the same
                // 98 pt band as the service cards: it is drawn for that height too
                if state.showingPlanDetail {
                    CardBackground(wash: nil)
                    ClaudePlanCardView(usage: state.claudePlanUsage)
                        .frame(height: Self.legacyCardHeight, alignment: .topLeading)
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
            .frame(width: 322)

            // Right card: agent pills
            CardBackground(wash: nil) {
                AgentPillsView(state: state)
            }
        }
        .onAppear { refreshHome() }
        .onChange(of: state.focusId) { _, new in
            showingIntegrationDetail = false
            withAnimation(.easeIn(duration: 0.16)) { state.showingPlanDetail = false }
            if new == "integration_github" { GithubPoller.shared.refreshIfStale() }
        }
        .onChange(of: state.view) { _, v in
            if v == .overview { refreshHome() } else { state.showingPlanDetail = false }
        }
        .onChange(of: state.mode) { _, m in
            if m != .expanded { state.showingPlanDetail = false }
            if m == .expanded && state.focusId == "integration_github" {
                GithubPoller.shared.refreshIfStale()
            }
        }
    }

    /// The home (spec §6): the conversations in progress, 3 at most, above the last choices, 5 at
    /// most, right of Klay. A permission or a question waiting has its own view, shown first.
    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            ConversationsView(sessions: state.sessions, hooksMissing: hooksMissing)
            if !state.recentChoices.isEmpty {
                ChoiceHistoryView(choices: state.recentChoices)
            }
        }
        .padding(.top, 9)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The card shrinks to the 98 pt frame of an inactive view while it fades out
        .clipped()
    }

    /// When the home shows (the island opens, or comes back to it): the roster is pruned, not on a
    /// timer, so a session that ended without telling (no hook since) is gone before the user reads
    /// the list; and the hooks are checked once, for the hint under an empty list.
    private func refreshHome() {
        state.pruneSessions()
        hooksMissing = !HookServer.claudeHooksInstalled()
    }

    /// Target of the ↗ button: the pull requests on GitHub, the Spotify app.
    private func openServiceTarget(_ task: AgentTask?) {
        switch task?.id {
        case "integration_github":
            NSWorkspace.shared.open(URL(string: "https://github.com/pulls")!)
        case "integration_spotify":
            SpotifyController.shared.openSpotify()
        default:
            break
        }
    }
}

// MARK: - Empty

struct EmptyStateView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Nothing running right now.")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Drop a file or window, or ask me anything.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#9398A1"))
                }
                Spacer()
                PrimaryButton("Ask Claude") {
                    state.view = .prompt
                }
            }
            .padding(.leading, 118)
            .padding(.trailing, 18)
        }
    }
}

// MARK: - Approval

struct ApprovalView: View {
    @ObservedObject var state: AppState
    /// The buttons act only once the request on screen has stayed `PendingRequest.armingDelay`:
    /// a click aimed at the card it replaced never answers it (CLAUDE.md, an explicit click).
    @State private var armed = false
    /// Counts the changes of the request on screen: only the latest one's delay arms the buttons.
    @State private var armGeneration = 0

    var approval: ApprovalInfo? { state.pendingApproval }

    /// The request whose card the open island shows, nil while it shows another view.
    private var requestOnScreen: Int? {
        state.mode == .expanded && state.view == .approval ? approval?.requestId : nil
    }

    /// Who asks: the project of the request's session (its roster row, whatever the shared pill is
    /// called now) on the color of its pill.
    private var who: AgentTask? {
        guard let approval else { return state.focusTask }
        let pill = state.tasks.first { $0.id == approval.pillId }
        let title = SessionRoster.title(of: approval.sessionId, in: state.sessions,
                                        fallback: pill?.name ?? "Session")
        let color = pill?.color ?? PillCatalog.definition(for: approval.pillId)?.color ?? "#C0C4CC"
        return AgentTask(id: approval.pillId, name: title, color: color, state: .approval,
                         steps: [], source: .agent)
    }

    var body: some View {
        ZStack {
            CardBackground(wash: .approval)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: who, label: "needs permission")
                CodeBlock(text: approval?.command ?? approval?.tool ?? "…")
                HStack(spacing: 8) {
                    SecondaryButton("Deny") {
                        HookServer.shared.sendApprovalDecision("deny")
                    }
                    PrimaryButton("Allow") {
                        HookServer.shared.sendApprovalDecision("allow")
                    }
                    SecondaryButton("Always") {
                        HookServer.shared.sendApprovalDecision("always")
                    }
                }
                .disabled(!armed)
                .opacity(armed ? 1 : 0.4)
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Disarmed whenever the request on screen changes (a newer one, the island opening on it),
        // armed 0.6 s later: one delayed call per change, no timer.
        .onChange(of: requestOnScreen, initial: true) { _, onScreen in
            armGeneration += 1
            armed = false
            guard onScreen != nil else { return }
            let generation = armGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + PendingRequest.armingDelay) {
                if armGeneration == generation { armed = true }
            }
        }
    }
}

// MARK: - Question

struct QuestionView: View {
    @ObservedObject var state: AppState
    @State private var questionIndex = 0
    // Per-question selected labels (empty = none chosen yet)
    @State private var selections: [[String]] = []
    // Per-question custom "Other…" text
    @State private var otherTexts: [String] = []
    // Per-question "Other…" mode active
    @State private var showOther: [Bool] = []
    @FocusState private var otherFieldFocused: Bool
    /// The buttons act only once the request on screen has stayed `PendingRequest.armingDelay`
    /// (see ApprovalView).
    @State private var armed = false
    @State private var armGeneration = 0

    var question: AskQuestion? { state.pendingQuestion }

    /// The request whose card the open island shows, nil while it shows another view.
    private var requestOnScreen: Int? {
        state.mode == .expanded && state.view == .question && question != nil
            ? state.pendingQuestionRequestId : nil
    }

    var body: some View {
        ZStack {
            CardBackground(wash: .question)
            if let q = question, !q.questions.isEmpty {
                let qi = min(questionIndex, q.questions.count - 1)
                let item = q.questions[qi]
                let isLast = qi == q.questions.count - 1
                let isMulti = item.multiSelect
                let curSel = qi < selections.count ? selections[qi] : []
                let curOther = qi < showOther.count ? showOther[qi] : false
                let curOtherText = qi < otherTexts.count ? otherTexts[qi] : ""
                let canProceed = !curSel.isEmpty || (curOther && !curOtherText.isEmpty)
                // A question from the Claude desktop app is answered in the app, not in a terminal.
                let replyLabel: LocalizedStringKey =
                    HookServer.shared.pendingQuestionPillId == HookRouting.desktopPillId
                    ? "Répondre dans Claude" : "Reply in terminal"

                VStack(alignment: .leading, spacing: 4) {
                    // Header row: agent name + question counter + "Reply in terminal" link
                    HStack(spacing: 4) {
                        AgentWho(task: nil, label: "Claude Code is asking")
                        Spacer(minLength: 4)
                        if q.questions.count > 1 {
                            Text("\(qi + 1)/\(q.questions.count)")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#6B7079"))
                        }
                        Button(replyLabel) { HookServer.shared.sendQuestionAsk() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .underline()
                            .disabled(!armed)
                            .opacity(armed ? 1 : 0.4)
                    }
                    // Optional short header label above question text
                    if !item.header.isEmpty {
                        Text(item.header)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    Text(item.question)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .fixedSize(horizontal: false, vertical: true)
                    // Options (wrapping) or "Other…" compact inline row, then Send/Next: disabled and
                    // dimmed until the request on screen is armed
                    Group {
                        if curOther {
                            HStack(spacing: 6) {
                                TextField("Your answer…", text: Binding(
                                    get: { qi < otherTexts.count ? otherTexts[qi] : "" },
                                    set: { v in if qi < otherTexts.count { otherTexts[qi] = v } }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#F5F6F8"))
                                .focused($otherFieldFocused)
                                .onAppear { otherFieldFocused = true }
                                .onSubmit { commitOtherAndProceed(q: q, qi: qi, isLast: isLast) }
                                .onExitCommand { if qi < showOther.count { showOther[qi] = false } }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Color.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                Button(isLast ? "Send" : "Next") {
                                    commitOtherAndProceed(q: q, qi: qi, isLast: isLast)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(curOtherText.isEmpty ? Color(hex: "#6B7079") : Color(hex: "#F5F6F8"))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Color.white.opacity(curOtherText.isEmpty ? 0.05 : 0.15))
                                .clipShape(Capsule())
                                .disabled(curOtherText.isEmpty)
                                Button { if qi < showOther.count { showOther[qi] = false } } label: {
                                    Text("✕").font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(Color(hex: "#6B7079"))
                            }
                        } else if item.hasDescriptions {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(item.options.enumerated()), id: \.offset) { idx, opt in
                                    let isSelected = curSel.contains(opt.label)
                                    Button {
                                        if isMulti {
                                            toggleSelection(qi: qi, label: opt.label)
                                        } else {
                                            selectAndProceed(q: q, qi: qi, label: opt.label, isLast: isLast)
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(opt.label)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(isSelected ? Color(hex: "#67E8F9") : Color(hex: "#F5F6F8"))
                                            if !opt.description.isEmpty {
                                                Text(opt.description)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(Color(hex: "#9AA0A8"))
                                                    .multilineTextAlignment(.leading)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(isSelected ? Color(hex: "#22D3EE").opacity(0.22) : Color.white.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color(hex: "#22D3EE").opacity(0.55) : Color.white.opacity(0.1), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [])
                                }
                                SecondaryButton("Other…") {
                                    if qi < showOther.count { showOther[qi] = true }
                                }
                            }
                        } else {
                            ChipFlowLayout(spacing: 6) {
                                ForEach(Array(item.options.enumerated()), id: \.offset) { idx, opt in
                                    let isSelected = curSel.contains(opt.label)
                                    if isMulti {
                                        Button {
                                            toggleSelection(qi: qi, label: opt.label)
                                        } label: {
                                            Text(opt.label)
                                                .font(.system(size: 12, weight: .medium))
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(isSelected ? Color(hex: "#22D3EE").opacity(0.22) : Color.white.opacity(0.07))
                                                .foregroundColor(isSelected ? Color(hex: "#67E8F9") : Color(hex: "#C5C8CD"))
                                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? Color(hex: "#22D3EE").opacity(0.55) : Color.white.opacity(0.1), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [])
                                    } else {
                                        SecondaryButton(verbatim: opt.label) {
                                            selectAndProceed(q: q, qi: qi, label: opt.label, isLast: isLast)
                                        }
                                        .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [])
                                    }
                                }
                                // "Other…" implicit free-text option
                                SecondaryButton("Other…") {
                                    if qi < showOther.count { showOther[qi] = true }
                                }
                            }
                        }
                        // Send/Next: only for multi-select (and not while "Other…" field is open)
                        if isMulti && !curOther {
                            PrimaryButton(isLast ? "Send" : "Next") {
                                proceedFromQuestion(q: q, qi: qi, isLast: isLast)
                            }
                            .disabled(!canProceed)
                            .opacity(canProceed ? 1 : 0.4)
                        }
                    }
                    .disabled(!armed)
                    .opacity(armed ? 1 : 0.4)
                }
                .padding(.leading, 116)
                .padding(.trailing, 16)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // No release on disappear: folding to compact or showing another view keeps the
        // question pending. It leaves when answered, sent to the terminal, or when its hook
        // connection closes or times out (HookServer). What was chosen so far is kept with it
        // (AppState.questionDraft): reopening the folded island resumes it, a new request starts blank.
        .onAppear { restoreDraft() }
        .onChange(of: state.pendingQuestionRequestId) { _, _ in restoreDraft() }
        .onChange(of: currentDraft) { _, draft in state.questionDraft = draft }
        // Disarmed whenever the request on screen changes, armed 0.6 s later (see ApprovalView).
        .onChange(of: requestOnScreen, initial: true) { _, onScreen in
            armGeneration += 1
            armed = false
            guard onScreen != nil else { return }
            let generation = armGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + PendingRequest.armingDelay) {
                if armGeneration == generation { armed = true }
            }
        }
    }

    /// The draft of the question on screen, as the card holds it now.
    private var currentDraft: QuestionDraft {
        QuestionDraft(requestId: state.pendingQuestionRequestId, index: questionIndex,
                      selections: selections, otherTexts: otherTexts, showOther: showOther)
    }

    /// Resumes the draft kept for the pending request, or starts blank for a new one.
    private func restoreDraft() {
        let draft = QuestionDraft.resuming(state.questionDraft, requestId: state.pendingQuestionRequestId,
                                           count: state.pendingQuestion?.questions.count ?? 0)
        questionIndex = draft.index
        selections = draft.selections
        otherTexts = draft.otherTexts
        showOther  = draft.showOther
    }

    private func toggleSelection(qi: Int, label: String) {
        guard qi < selections.count else { return }
        if let i = selections[qi].firstIndex(of: label) {
            selections[qi].remove(at: i)
        } else {
            selections[qi].append(label)
        }
    }

    // Single-select: pick a label and immediately advance/send
    private func selectAndProceed(q: AskQuestion, qi: Int, label: String, isLast: Bool) {
        guard qi < selections.count else { return }
        selections[qi] = [label]
        if isLast { sendAnswers(q: q) } else { withAnimation { questionIndex = qi + 1 } }
    }

    // Multi-select Send/Next button
    private func proceedFromQuestion(q: AskQuestion, qi: Int, isLast: Bool) {
        if isLast { sendAnswers(q: q) } else { withAnimation { questionIndex = qi + 1 } }
    }

    // "Other…" confirm
    private func commitOtherAndProceed(q: AskQuestion, qi: Int, isLast: Bool) {
        let text = qi < otherTexts.count ? otherTexts[qi] : ""
        guard !text.isEmpty else { return }
        if qi < selections.count { selections[qi] = [text] }
        if isLast {
            sendAnswers(q: q)
        } else {
            if qi < showOther.count { showOther[qi] = false }
            withAnimation { questionIndex = qi + 1 }
        }
    }

    private func sendAnswers(q: AskQuestion) {
        let answers = AskQuestion.buildAnswers(questions: q.questions, selections: selections)
        HookServer.shared.sendQuestionAnswers(answers)
    }
}

// MARK: - Error

struct ErrorView: View {
    @ObservedObject var state: AppState

    /// The pill of the session that failed (nil once the pill is gone), else the pill in focus.
    private var pillTask: AgentTask? {
        guard let session = state.failedSession else { return state.focusTask }
        return state.tasks.first { $0.id == session.pillId }
    }

    /// Who failed: the project of that session on the color of its pill.
    private var who: AgentTask? {
        guard let session = state.failedSession else { return state.focusTask }
        let color = pillTask?.color ?? PillCatalog.definition(for: session.pillId)?.color ?? "#C0C4CC"
        return AgentTask(id: session.pillId, name: session.title, color: color, state: .error,
                         steps: [], source: .agent)
    }

    /// The error text of the StopFailure hook, else a line saying there is none.
    private var detail: Text {
        if let text = state.failedSession?.lastAction, !text.isEmpty { return Text(verbatim: text) }
        return Text("No error details available.")
    }

    var body: some View {
        ZStack {
            CardBackground(wash: .error)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: who, label: "Failed")
                Text("Claude s'est arrêté sur une erreur")
                    .font(.system(size: 15, weight: .semibold))
                detail
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#FF8D97"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    SessionOpenButton(session: state.failedSession, pillTask: pillTask)
                    SecondaryButton("OK") {
                        NotificationCenter.default.post(name: .islandCollapse, object: nil)
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Brings the Claude desktop app forward (or launches it) — target of the Claude Desktop pill.
private let claudeDesktopBundleId = "com.anthropic.claudefordesktop"

private func openClaudeDesktopApp() {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeDesktopBundleId) {
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }
}

/// The open button of the finished and error views, then the island folds. A session of the Claude
/// desktop app opens the app (« Open Claude »); a Claude Code session brings forward the app it runs
/// in, its terminal or its editor, then any known terminal (« Open terminal »). `session` is the
/// session the view tells about, nil for the pill in focus (`pillTask`).
private struct SessionOpenButton: View {
    let session: SessionRow?
    let pillTask: AgentTask?

    /// Sessions from the Claude desktop app live there, not in a terminal.
    private var isDesktopSession: Bool {
        (session?.pillId ?? pillTask?.id) == HookRouting.desktopPillId
    }

    var body: some View {
        if isDesktopSession {
            PrimaryButton("Open Claude") {
                openClaudeDesktopApp()
                NotificationCenter.default.post(name: .islandCollapse, object: nil)
            }
        } else {
            PrimaryButton("Open terminal") {
                // The app the session runs in (its terminal or its editor), then any known terminal.
                // The session's own host: its pill may carry another session now.
                let opened: Bool
                if let session {
                    opened = ClaudeHost.activate(session.hostBundleId)
                        || TerminalTarget.activate(sessionBundleId: session.hostBundleId)
                } else {
                    let task = pillTask
                    opened = (task?.id == "integration_claude" && ClaudeHost.activate(task?.hostApp))
                        || TerminalTarget.activate(sessionBundleId: task?.sessionBundleId)
                }
                if !opened {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
                NotificationCenter.default.post(name: .islandCollapse, object: nil)
            }
        }
    }
}

// MARK: - Finished

struct FinishedView: View {
    @ObservedObject var state: AppState

    /// The pill of the session that finished (nil once the pill is gone), else the pill in focus.
    private var pillTask: AgentTask? {
        guard let session = state.finishedSession else { return state.focusTask }
        return state.tasks.first { $0.id == session.pillId }
    }

    /// Who finished: the project of that session on the color of its pill.
    private var who: AgentTask? {
        guard let session = state.finishedSession else { return state.focusTask }
        let color = pillTask?.color ?? PillCatalog.definition(for: session.pillId)?.color ?? "#C0C4CC"
        return AgentTask(id: session.pillId, name: session.title, color: color, state: .finished,
                         steps: [], source: .agent)
    }

    var body: some View {
        ZStack {
            CardBackground(wash: .finished)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: who, label: "Claude Code finished")
                Text({
                    if let session = state.finishedSession {
                        return session.lastAction.isEmpty ? String(localized: "Session finished") : session.lastAction
                    }
                    if let fl = state.focusTask?.finalLine { return fl }
                    if let s = state.focusTask?.steps.last { return s }
                    return String(localized: "Session finished")
                }())
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    SessionOpenButton(session: state.finishedSession, pillTask: pillTask)
                    SecondaryButton("OK") {
                        NotificationCenter.default.post(name: .islandCollapse, object: nil)
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Confused

struct ConfusedView: View {
    var body: some View {
        ZStack {
            CardBackground(wash: .dizzy)
            VStack(alignment: .leading, spacing: 5) {
                Text("Too many hits at once.").font(.system(size: 15, weight: .semibold))
                Text("Give me a sec — back to work in three seconds.")
                    .font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1"))
            }
            .padding(.leading, 128)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Upload (drop zone)

struct UploadView: View {
    @ObservedObject var state: AppState
    @State private var dashPhase: CGFloat = 0
    @State private var breathAngle: Double = 0
    // Timer only runs while this is the active tab — killed on deactivation
    @State private var animTimer: Timer? = nil

    private var borderOpacity: Double {
        let breathe = 0.11 + 0.04 * (sin(breathAngle) * 0.5 + 0.5)
        return state.fileDragOver ? 0.65 : breathe
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#0E0F11"))
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    state.fileDragOver
                        ? Color(hex: "#22C55E").opacity(borderOpacity)
                        : Color.white.opacity(borderOpacity),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5], dashPhase: dashPhase)
                )
            RoundedRectangle(cornerRadius: 20)
                .fill(RadialGradient(
                    colors: [Color(hex: "#22C55E").opacity(state.fileDragOver ? 0.13 : 0), Color.clear],
                    center: .bottom, startRadius: 0, endRadius: 200
                ))
            // The invitation: Klay himself, arms open, then the text (same figure as the
            // drag-over canvas, UploadCanvasView, drawn smaller). This view gets the 98 pt
            // content frame, not the canvas' 124 pt card: figure 56 pt in a 64 pt frame
            // (4 pt of room each side for the bob), 6 pt gap, ~16 pt of text = ~86 pt, so
            // about 6 pt of margin above and below inside the dashed border.
            VStack(spacing: 6) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    Canvas { ctx, size in
                        KlayPaint.drawDropInvite(ctx, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                                 height: 56, time: tl.date.timeIntervalSinceReferenceDate)
                    }
                }
                .frame(width: 140, height: 64)
                Text("Dépose ton fichier")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(state.fileDragOver ? Color(hex: "#34D399") : Color(hex: "#D5D7DB"))
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: state.view) { _, newView in
            newView == .upload ? startTimer() : stopTimer()
        }
        .onAppear {
            if state.view == .upload { startTimer() }
        }
        .onDisappear { stopTimer() }
    }

    private func startTimer() {
        guard animTimer == nil else { return }
        // 20 fps — smooth enough for slow dash, 3× lighter than 60fps
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0/20.0, repeats: true) { _ in
            dashPhase  += 1.0          // 20 pt/s march
            breathAngle += 0.9 / 20.0  // advance sin phase at 0.9 rad/s
        }
    }

    private func stopTimer() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

// MARK: - Uploading

struct UploadingView: View {
    @ObservedObject var state: AppState

    // Bar geometry in content coords (content has 10pt H padding each side).
    // Island bar: left=36, right=562 (640-78), width=526.
    // Content bar: left=26, width=526.
    // barTop=58 → island y = content_start(42)+58 = 100; bot cy=103 (center = barTop+3).
    private let barLeft: CGFloat  = 26
    private let barWidth: CGFloat = 526
    private let barTop: CGFloat   = 58

    var body: some View {
        // TimelineView fires at display refresh rate — progress derived from elapsed wall time,
        // not from @Published uploadProgress (which only flips to 1.0 at completion).
        TimelineView(.animation) { tl in
            let elapsed: Double = {
                guard let start = state.uploadStartTime else { return 0 }
                return tl.date.timeIntervalSince(start)
            }()
            let t        = min(1.0, max(0, elapsed / state.uploadDuration))
            let progress = CGFloat(t * (2 - t))          // ease-out quad
            let fillWidth = max(0, barWidth * progress)
            let isDone   = state.uploadProgress >= 0.999  // only true after handle() sets it

            ZStack(alignment: .topLeading) {
                // Background: dark base
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "#141518"))

                // Permanent green radial wash — brighter at completion
                RoundedRectangle(cornerRadius: 20)
                    .fill(RadialGradient(
                        colors: [Color(hex: "#34D399").opacity(isDone ? 0.28 : 0.14), Color.clear],
                        center: UnitPoint(x: 0.5, y: 1.4),
                        startRadius: 0,
                        endRadius: 260
                    ))

                // Bar track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.09))
                    .frame(width: barWidth, height: 6)
                    .offset(x: barLeft, y: barTop)

                // Bar fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#1FA87A"), Color(hex: "#34D399")],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: fillWidth, height: 6)
                    .offset(x: barLeft, y: barTop)

                // Glow trail behind dot leading edge
                if progress > 0.01 {
                    Ellipse()
                        .fill(Color(hex: "#6EE7B7").opacity(0.45))
                        .frame(width: 28, height: 12)
                        .blur(radius: 5)
                        .offset(x: barLeft + fillWidth - 14, y: barTop - 3)
                }

                // Text row — filename + % (above bar)
                HStack(spacing: 0) {
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#34D399"))
                        Text("  \(state.droppedFile?.name ?? "File")")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Color(hex: "#34D399"))
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text(String(format: String(localized: "Uploading %@"), state.droppedFile?.name ?? "file"))
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(hex: "#A9ADB5"))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(Int(progress * 100)) %")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Color(hex: "#A9ADB5"))
                            .monospacedDigit()
                    }
                }
                .frame(width: barWidth)
                .offset(x: barLeft, y: barTop - 22)

                // Subtle top border (same as CardBackground)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.035), lineWidth: 1)
            }
        }
    }
}

// MARK: - Choose

struct ChooseView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                let fileName = state.droppedFile?.name ?? "file"
                Text(String(format: String(localized: "file.ready %@"), fileName))
                    .font(.system(size: 14, weight: .semibold))
                Text("What do you want to do with it?").font(.system(size: 12.5)).foregroundColor(Color(hex: "#9398A1"))
                HStack(spacing: 8) {
                    PrimaryButton("Ask a question") { state.view = .prompt }
                    SecondaryButton("Send by email") { state.view = .mail }
                }
            }
            .padding(.leading, 98)
            .padding(.trailing, 18)
        }
    }
}

// MARK: - Mail

struct MailView: View {
    @ObservedObject var state: AppState
    @State private var to: String = ""
    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var statusMsg: String = ""

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("New email").font(.system(size: 12, weight: .semibold))
                    if let name = state.droppedFile?.name {
                        Text(String(format: String(localized: "mail.with %@"), name))
                            .font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1).truncationMode(.middle)
                    }
                }

                MailField(label: "To", placeholder: "address@example.com", text: $to)
                MailField(label: "Subject", placeholder: state.droppedFile?.name ?? "Subject", text: $subject)

                // Body — TextEditor scrolls internally when text overflows
                TextEditor(text: $bodyText)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .frame(height: 44)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if !statusMsg.isEmpty {
                    Text(statusMsg).font(.system(size: 11)).foregroundColor(Color(hex: "#FF8D97"))
                }

                HStack(spacing: 8) {
                    PrimaryButton("Send") { sendMail() }
                    SecondaryButton("Cancel") { state.view = .choose }
                }
            }
            .padding(.leading, 92)
            .padding(.trailing, 18)
            .padding(.vertical, 8)
        }
        .onAppear { subject = state.droppedFile?.name ?? "" }
    }

    private func sendMail() {
        guard !to.isEmpty else { statusMsg = String(localized: "Missing recipient."); return }
        let subj = subject.isEmpty ? (state.droppedFile?.name ?? "File") : subject
        sendViaAppleMail(to: to, subject: subj)
    }

    private func sendViaAppleMail(to: String, subject: String) {
        func asEscape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }

        let bodyLines = bodyText.isEmpty ? [""] : bodyText.components(separatedBy: "\n")
        let bodyExpr = bodyLines.map { "\"\(asEscape($0))\"" }.joined(separator: " & linefeed & ")
            + " & return & return"

        let attachBlock: String
        if let url = state.droppedFile?.url,
           FileManager.default.fileExists(atPath: url.path) {
            let escapedPath = asEscape(url.path)
            attachBlock = "make new attachment with properties {file name:(POSIX file \"\(escapedPath)\")} at after the last paragraph of content"
        } else {
            attachBlock = ""
        }

        let script = """
        tell application "Mail"
            set m to make new outgoing message with properties {subject:"\(asEscape(subject))", visible:false}
            set content of m to \(bodyExpr)
            tell m
                make new to recipient at end of to recipients with properties {address:"\(asEscape(to))"}
                \(attachBlock)
            end tell
            delay 1
            send m
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if err == nil { onSuccess(recipient: to) }
        else { statusMsg = "Mail error: \(err?["NSAppleScriptErrorMessage"] as? String ?? "unknown")" }
    }

    private func onSuccess(recipient: String) {
        SoundEngine.shared.play("send")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.wink)
        state.noteMessage = "Email sent to \(recipient)."
        state.view = .note
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        }
    }
}

// MARK: - Prompt (chat)

struct PromptView: View {
    @ObservedObject var state: AppState
    @State private var text: String = ""
    @FocusState private var focused: Bool

    @State private var dictation = MacDictation()
    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .searching)

            VStack(alignment: .leading, spacing: 6) {
                if let ctx = state.promptContext {
                    ContextChip(context: ctx).padding(.top, 4)
                }

                if !state.chatHistory.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(state.chatHistory) { msg in
                                    ChatBubble(message: msg).id(msg.id)
                                }
                                if state.stateOverride != nil {
                                    HStack { TypingDotsView(); Spacer(minLength: 32) }
                                        .id("typing")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onChange(of: state.chatHistory) { _, _ in
                            if let last = state.chatHistory.last(where: { !$0.content.isEmpty }) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                        .onChange(of: state.stateOverride) { _, v in
                            if v != nil {
                                withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                            } else if let last = state.chatHistory.last(where: { !$0.content.isEmpty }) {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .onAppear {
                            if let last = state.chatHistory.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                }

                HStack(spacing: 8) {
                    TextField(state.chatHistory.isEmpty ? String(localized: "Ask me anything…") : String(localized: "Continue…"), text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focused)
                        .onSubmit { sendMessage() }

                    // Dictate instead of typing (on-device speech recognition when available)
                    Button {
                        Task { await dictation.toggle(startingFrom: text) }
                    } label: {
                        Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(dictation.isRecording ? Color(hex: "#F4505E") : Color(hex: "#8E939C"))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(dictation.isRecording ? String(localized: "Stop dictation") : String(localized: "Dictate"))
                    .onChange(of: dictation.transcript) { _, _ in
                        if dictation.isRecording { text = dictation.text }
                    }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#0B0C0E"))
                    }
                    .buttonStyle(SendButtonStyle())
                    .disabled(text.isEmpty)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .simultaneousGesture(TapGesture().onEnded { focused = true })
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .padding(.bottom, 10)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .islandSendMessage)) { _ in
            guard state.view == .prompt else { return }
            sendMessage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandNewConversation)) { _ in
            guard state.view == .prompt else { return }
            text = ""
            state.chatHistory = []
            ClaudeService.shared.clearConversation()
            focused = true
        }
    }

    private func sendMessage() {
        dictation.stop()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        text = ""
        focused = false
        state.chatHistory.append(ChatMessage(role: .user, content: query))
        state.stateOverride = .thinking
        Task {
            await ClaudeService.shared.chat(query: query, context: state.promptContext, state: state)
            await MainActor.run { focused = true }
        }
    }
}


// MARK: - Chip flow layout

/// Wrapping horizontal flow layout — used by QuestionView.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let r = rows(maxW: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return r.size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let r = rows(maxW: bounds.width, subviews: subviews)
        for (idx, pt) in r.placements.enumerated() {
            subviews[idx].place(at: CGPoint(x: bounds.minX + pt.x, y: bounds.minY + pt.y), proposal: .unspecified)
        }
    }
    private func rows(maxW: CGFloat, subviews: Subviews) -> (size: CGSize, placements: [(x: CGFloat, y: CGFloat)]) {
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        var pts: [(x: CGFloat, y: CGFloat)] = []
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
            pts.append((x: x, y: y))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: max(maxX, 0), height: y + lineH), pts)
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        if !message.content.isEmpty {
            HStack(alignment: .top) {
                if message.role == .user {
                    Spacer(minLength: 32)
                    Text(message.content)
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#F1F2F4"))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ChatMarkdownView(markdown: message.content)
                    Spacer(minLength: 8)
                }
            }
        }
    }
}

struct TypingDotsView: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(hex: "#6B7079"))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase ? 1.2 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.14),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 4)
        .onAppear { phase = true }
    }
}

// MARK: - Searching

struct SearchingView: View {
    @ObservedObject var state: AppState

    var label: String {
        switch state.promptContext {
        case .window(_, let title, _): return String(format: String(localized: "Claude is reading %@…"), title)
        case .file(let name, _):       return String(format: String(localized: "Claude is reading %@…"), name)
        case nil:                      return String(localized: "Claude is searching…")
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .searching)

            VStack(alignment: .leading, spacing: 8) {
                if let ctx = state.promptContext {
                    ContextChip(context: ctx)
                }
                ShimmeringText(label)
                    .font(.system(size: 13.5))
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
        }
    }
}

// MARK: - Result

struct ResultView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .finished)

            if let result = state.searchResult {
                VStack(alignment: .leading, spacing: 7) {
                    Text(result.title)
                        .font(.system(size: 15, weight: .semibold))

                    VStack(spacing: 4) {
                        ForEach(result.items.prefix(3), id: \.label) { item in
                            HStack {
                                Text(item.label).font(.system(size: 12.5, weight: .semibold))
                                Spacer()
                                Text(item.detail).font(.system(size: 12.5)).foregroundColor(Color(hex: "#9398A1"))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    if let note = result.note {
                        Text(note).font(.system(size: 11)).foregroundColor(Color(hex: "#6E737C"))
                    }

                    HStack(spacing: 8) {
                        // The URL comes from the model, which may have read attacker-controlled
                        // files or pages: only plain web links may leave the app.
                        let openURL = safeWebURL(result.items.first?.url)
                        PrimaryButton("Open") {
                            if let openURL { NSWorkspace.shared.open(openURL) }
                        }
                        .disabled(openURL == nil)
                        .help(openURL?.absoluteString ?? "")
                        SecondaryButton("Copy") {
                            let text = result.items.map { "\($0.label): \($0.detail)" }.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        SecondaryButton("Close") { state.view = state.tasks.isEmpty ? .empty : .overview }
                    }
                }
                .padding(.leading, 84)
                .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - Note (short message, auto-closes)

struct NoteView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.noteMessage ?? "")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.leading, 98)
        }
    }
}

// MARK: - Integration card (overview left card when an integration pill is focused)

struct IntegrationCardView: View {
    let task: AgentTask
    @Binding var showingDetail: Bool
    @ObservedObject private var appState = AppState.shared
    @State private var githubDetailSection: GitHubDetailSection = .myPRs

    // The overview shows this card for the service pills only (GitHub, Spotify): the Claude
    // pills show the home instead.
    private var isConfigured: Bool {
        switch task.id {
        case "integration_github":  return KeychainStore.shared.get("github-token")   != nil
        default: return false
        }
    }

    private var openURL: URL? {
        switch task.id {
        case "integration_github":  return URL(string: "https://github.com")
        default: return nil
        }
    }

    // GitHub with stats or pulse loaded
    private var githubHasData: Bool {
        task.id == "integration_github" && (appState.githubPulse != nil || appState.githubStats != nil)
    }

    // GitHub with pulse loaded (richer card)
    private var githubHasPulse: Bool {
        task.id == "integration_github" && appState.githubPulse != nil
    }

    // Spotify: its own card for every state (playing, idle, not installed, Automation denied)
    private var isSpotify: Bool {
        return task.id == "integration_spotify"
    }

    private var statusDot: Color {
        if PillCatalog.definition(for: task.id)?.comingSoon == true { return Color(hex: "#6B7079") }
        return isConfigured ? Color(hex: "#22C55E") : Color(hex: "#F4505E")
    }

    private var statusLabel: String {
        if PillCatalog.definition(for: task.id)?.comingSoon == true { return String(localized: "Coming soon") }
        return isConfigured ? String(localized: "Connected · loading…") : String(localized: "Key not configured")
    }

    var body: some View {
        if showingDetail && githubHasPulse {
            GitHubDetailView(
                section: githubDetailSection,
                pulse: appState.githubPulse!,
                activity: appState.githubActivity,
                stats: appState.githubStats,
                onBack: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
                }
            )
            .transition(.opacity)
        } else if githubHasPulse {
            GitHubPulseCardView(
                pulse: appState.githubPulse!,
                stats: appState.githubStats,
                activity: appState.githubActivity,
                onTapSection: { section in
                    githubDetailSection = section
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
                }
            )
            .transition(.opacity)
        } else if githubHasData {
            GitHubStatsCardView(stats: appState.githubStats!)
                .transition(.opacity)
        } else if isSpotify {
            SpotifyCardView()
                .transition(.opacity)
        } else {
            // Idle / not connected view — slides in from left when returning from detail
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: task.color))
                        .frame(width: 7, height: 7)
                    Text(PillCatalog.definition(for: task.id)?.name ?? task.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Text(PillCatalog.definition(for: task.id)?.subtitle ?? "Integration")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                HStack(spacing: 5) {
                    Circle().fill(statusDot).frame(width: 5, height: 5)
                    Text(statusLabel)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                .padding(.leading, 108)
                .padding(.top, 2)

                HStack(spacing: 8) {
                    if let url = openURL {
                        Button("Open \(task.name)") { NSWorkspace.shared.open(url) }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    // Settings button: shown when not configured
                    if !isConfigured {
                        Button("Settings…") {
                            let section: String
                            switch PillCatalog.definition(for: task.id)?.category {
                            case .workspace, .agent: section = "agents"
                            default:                 section = "integrations"
                            }
                            NotificationCenter.default.post(name: .openFullSettings, object: section)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 108)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .transition(.opacity)
        }
    }
}

// MARK: - GitHub Pulse Card View

private func ciWorstState(_ prs: [GitHubPR]) -> CIState {
    if prs.contains(where: { $0.ci == .failure }) { return .failure }
    if prs.contains(where: { $0.ci == .pending }) { return .pending }
    if prs.contains(where: { $0.ci == .success }) { return .success }
    return .unknown
}

private func ciColor(_ state: CIState) -> String {
    switch state {
    case .failure: return "#F4505E"
    case .pending: return "#F5A524"
    case .success: return "#22C55E"
    case .unknown: return "#6B7079"
    }
}

private func mainCIWorst(_ repos: [GitHubRepoCI]) -> CIState {
    if repos.contains(where: { $0.ci == .failure }) { return .failure }
    if repos.contains(where: { $0.ci == .pending }) { return .pending }
    if repos.contains(where: { $0.ci == .success }) { return .success }
    return .unknown
}

struct GitHubPulseCardView: View {
    let pulse: GitHubPulse
    let stats: GitHubStats?
    let activity: GitHubActivity?
    let onTapSection: (GitHubDetailSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#F4505E"))
                    .frame(width: 7, height: 7)
                Text("GitHub")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                if let s = stats {
                    // Stars + 7-day mini-row → opens Activity detail
                    Button(action: { onTapSection(.activity) }) {
                        HStack(spacing: 4) {
                            Text("★ \(formatCount(s.totalStars))")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#8E939C"))
                                .lineLimit(1)
                            if let act = activity {
                                HStack(spacing: 2) {
                                    ForEach(act.lastDays(7), id: \.date) { day in
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(contributionColor(day.level))
                                            .frame(width: 7, height: 7)
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else if let act = activity {
                    // No stats yet but activity loaded — show mini-row only
                    Button(action: { onTapSection(.activity) }) {
                        HStack(spacing: 2) {
                            ForEach(act.lastDays(7), id: \.date) { day in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(contributionColor(day.level))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Overview")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Stat rows
            VStack(alignment: .leading, spacing: 4) {
                // My PRs
                let prWorst = ciWorstState(pulse.myPRs)
                let prValue: String = {
                    let n = pulse.myPRs.count
                    if n == 0 { return "0" }
                    let failing = pulse.myPRs.filter { $0.ci == .failure }.count
                    let pending = pulse.myPRs.filter { $0.ci == .pending }.count
                    if failing > 0 { return "\(n) · \(failing) failing" }
                    if pending > 0 { return "\(n) · running" }
                    return "\(n)"
                }()
                GitHubStatRow(
                    icon: "arrow.triangle.pull", iconColor: ciColor(prWorst),
                    label: String(localized: "My PRs"), value: prValue
                ) { onTapSection(.myPRs) }

                // To review
                let reviewCount = pulse.toReview.count
                GitHubStatRow(
                    icon: "eye",
                    iconColor: reviewCount > 0 ? "#8AB4F8" : "#6B7079",
                    label: String(localized: "To review"),
                    value: "\(reviewCount)"
                ) { onTapSection(.toReview) }

                // Default branch CI
                let mainWorst = mainCIWorst(pulse.mainCI)
                let (ciIcon, ciIconColor, ciValue): (String, String, String) = {
                    switch mainWorst {
                    case .failure:
                        let n = pulse.mainCI.filter { $0.ci == .failure }.count
                        return ("xmark.octagon.fill", "#F4505E", "\(n) failing")
                    case .pending:
                        return ("checkmark.seal.fill", "#F5A524", "running")
                    case .success:
                        return ("checkmark.seal.fill", "#22C55E", "all green")
                    case .unknown:
                        return ("checkmark.seal.fill", "#6B7079", pulse.mainCI.isEmpty ? "no repos" : "unknown")
                    }
                }()
                GitHubStatRow(
                    icon: ciIcon, iconColor: ciIconColor,
                    label: "Default branch CI", value: ciValue
                ) { onTapSection(.mainCI) }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .clipped()
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

private struct GitHubStatRow: View {
    let icon: String
    let iconColor: String
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: iconColor))
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GitHub Detail View

struct GitHubDetailView: View {
    let section: GitHubDetailSection
    let pulse: GitHubPulse
    let activity: GitHubActivity?
    let stats: GitHubStats?
    let onBack: () -> Void
    @ObservedObject private var appState = AppState.shared

    private var title: String {
        switch section {
        case .myPRs:    return String(localized: "My PRs")
        case .toReview: return String(localized: "To review")
        case .mainCI:   return "Default branch CI"
        case .activity: return String(localized: "Activity")
        }
    }

    private var items: [GitHubPR] {
        switch section {
        case .myPRs:    return pulse.myPRs
        case .toReview: return pulse.toReview
        case .mainCI, .activity: return []
        }
    }

    private var repoItems: [GitHubRepoCI] {
        section == .mainCI ? pulse.mainCI : []
    }

    private var totalItems: Int { items.count + repoItems.count }

    var body: some View {
        if section == .activity {
            GitHubActivityDetailContent(
                activity: activity,
                stats: stats,
                login: pulse.login,
                onBack: onBack
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 6) {
                    Button(action: onBack) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8, weight: .medium))
                            Text(title)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 12)

                // List
                if items.isEmpty && repoItems.isEmpty {
                    Text("Nothing here")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .padding(.top, 8)
                        .padding(.leading, 108)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, pr in
                                GitHubPRRowView(pr: pr, showCI: section == .myPRs,
                                               selected: appState.cardSelection == idx)
                            }
                            ForEach(Array(repoItems.enumerated()), id: \.element.repo) { idx, repo in
                                GitHubRepoCIRowView(repo: repo,
                                                   selected: appState.cardSelection == items.count + idx)
                            }
                        }
                    }
                    .frame(maxHeight: 60)  // 3 rows × 20 pt; rest scrolls
                    .mask(
                        Group {
                            if totalItems > 3 {
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black, location: 0.8),
                                        .init(color: .clear,  location: 1.0)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            } else {
                                Color.black
                            }
                        }
                    )
                    .padding(.top, 4)
                    .padding(.leading, 108)
                    .padding(.trailing, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .clipped()
            .onAppear {
                GithubPoller.shared.refreshIfStale()
                appState.cardItemCount = totalItems
            }
            .onDisappear { appState.cardItemCount = 0 }
            .onReceive(NotificationCenter.default.publisher(for: .islandActivateCardSelection)) { _ in
                guard let sel = appState.cardSelection else { return }
                if sel < items.count {
                    let pr = items[sel]
                    if let url = safeWebURL(pr.url), url.host == "github.com" {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    let repoIdx = sel - items.count
                    guard repoIdx < repoItems.count else { return }
                    let repo = repoItems[repoIdx]
                    let actionsURL = repo.url.hasSuffix("/") ? repo.url + "actions" : repo.url + "/actions"
                    if let url = safeWebURL(actionsURL), url.host == "github.com" {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .onExitCommand { onBack() }
        }
    }
}

// MARK: - GitHub Activity Detail

private struct GitHubActivityDetailContent: View {
    let activity: GitHubActivity?
    let stats: GitHubStats?
    let login: String
    let onBack: () -> Void

    @State private var hoveredDay: ContributionDay? = nil

    // Dynamic grid: s=7pt, spacing=1.5pt; numWeeks = floor((202 + 1.5) / (7 + 1.5)) = 23
    private let squareSize: CGFloat = 7
    private let spacing: CGFloat = 1.5
    private var numWeeks: Int { Int((202 + spacing) / (squareSize + spacing)) }

    private var headerRight: String {
        if let day = hoveredDay {
            let label: String
            switch day.count {
            case 0:  label = String(localized: "No contributions")
            case 1:  label = "1 contribution"
            default: label = "\(day.count) contributions"
            }
            return "\(activityDateLabel(day.date)) · \(label)"
        }
        guard let act = activity else { return "" }
        let total = activityTotalLabel(act.total)
        if let s = stats { return "\(total) past year · \(s.totalRepos) repos" }
        return "\(total) past year"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .medium))
                        Text("Activity")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#F5F6F8"))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 2)
                if activity != nil {
                    Button(action: {
                        let urlStr = "https://github.com/\(login)"
                        if let url = safeWebURL(urlStr), url.host == "github.com" {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text(headerRight)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 12)

            // Grid
            if let act = activity {
                let weeks = act.lastWeeks(numWeeks)
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(weeks.indices, id: \.self) { wi in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { dow in
                                if let day = weeks[wi].first(where: { $0.weekday == dow }) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(contributionColor(day.level))
                                        .frame(width: squareSize, height: squareSize)
                                        .onHover { hovering in hoveredDay = hovering ? day : nil }
                                        .onTapGesture {
                                            hoveredDay = (hoveredDay?.date == day.date) ? nil : day
                                        }
                                } else {
                                    Color.clear.frame(width: squareSize, height: squareSize)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 5)
                .padding(.leading, 108)
                .padding(.trailing, 12)
            } else {
                Text("Loading…")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .padding(.top, 8)
                    .padding(.leading, 108)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .clipped()
        .onAppear { GithubPoller.shared.refreshActivityIfStale() }
        .onExitCommand { onBack() }
    }

    private func activityDateLabel(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]), month >= 1 && month <= 12,
              let day   = Int(parts[2]) else { return dateStr }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return "\(months[month - 1]) \(day)"
    }

    private func activityTotalLabel(_ n: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.locale = Locale(identifier: "en_US")
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private func contributionColor(_ level: Int) -> Color {
    switch level {
    case 1: return Color(hex: "#0E4429")
    case 2: return Color(hex: "#006D32")
    case 3: return Color(hex: "#26A641")
    case 4: return Color(hex: "#39D353")
    default: return Color.white.opacity(0.06)
    }
}

private func ghCIDot(_ ci: CIState) -> Color {
    switch ci {
    case .failure: return Color(hex: "#F4505E")
    case .pending: return Color(hex: "#F5A524")
    case .success: return Color(hex: "#22C55E")
    case .unknown: return Color.clear
    }
}

private struct GitHubPRRowView: View {
    let pr: GitHubPR
    let showCI: Bool
    var selected: Bool = false

    var body: some View {
        Button(action: {
            if let url = safeWebURL(pr.url), url.host == "github.com" {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 5) {
                if showCI {
                    Circle()
                        .fill(ghCIDot(pr.ci))
                        .frame(width: 5, height: 5)
                        .opacity(pr.ci == .unknown ? 0 : 1)
                } else {
                    Spacer().frame(width: 5)
                }
                Text("\(pr.repo.components(separatedBy: "/").last ?? pr.repo)#\(pr.number)")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(1)
                Text(pr.title)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if pr.isDraft {
                    Text("Draft")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct GitHubRepoCIRowView: View {
    let repo: GitHubRepoCI
    var selected: Bool = false

    private var ciStateWord: String? {
        switch repo.ci {
        case .failure: return "failing"
        case .pending: return "running"
        case .success: return "passing"
        case .unknown: return nil
        }
    }

    var body: some View {
        Button(action: {
            let actionsURL = repo.url.hasSuffix("/") ? repo.url + "actions" : repo.url + "/actions"
            if let url = safeWebURL(actionsURL), url.host == "github.com" {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(ghCIDot(repo.ci))
                    .frame(width: 5, height: 5)
                    .opacity(repo.ci == .unknown ? 0 : 1)
                Text(repo.repo.components(separatedBy: "/").last ?? repo.repo)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(1)
                Text(repo.branch)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let word = ciStateWord {
                    Text(word)
                        .font(.system(size: 10))
                        .foregroundColor(ghCIDot(repo.ci))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GitHub Stats Card View

struct GitHubStatsCardView: View {
    let stats: GitHubStats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#F4505E"))
                    .frame(width: 7, height: 7)
                Text("GitHub")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Overview")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Stats rows
            VStack(alignment: .leading, spacing: 5) {
                StatRow(icon: "star.fill", color: "#F5A524",
                        label: "Total stars", value: formatCount(stats.totalStars))
                StatRow(icon: "square.stack.fill", color: "#6B7079",
                        label: "Repositories", value: "\(stats.totalRepos)")
            }
            .padding(.top, 8)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

private struct StatRow: View {
    let icon: String
    let color: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: color))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Agent pills (overview right card)

struct AgentPillsView: View {
    @ObservedObject var state: AppState
    @State private var swapping = false

    private var others: [AgentTask] {
        state.tasks.filter { $0.id != state.focusId }
    }

    private var displayTasks: [AgentTask] {
        Array(others.prefix(4))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(displayTasks) { task in
                    if task.id == "integration_spotify" {
                        SpotifyPill(task: task, swapping: $swapping) {
                            swapping = true
                            state.setFocus(task.id)
                            SoundEngine.shared.play("blip")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
                        }
                    } else {
                        AgentPill(task: task, state: state, swapping: $swapping) {
                            swapping = true
                            state.setFocus(task.id)
                            SoundEngine.shared.play("blip")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentPill: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    private var effectiveColor: String { task.color }

    // The Claude Code pill shows "Claude Code" regardless of project name
    private var displayName: String {
        task.id == "integration_claude" ? ClaudeHost.pillName : task.name
    }

    var body: some View {
        Button(action: { onTap() }) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Capsule()
                        .fill(isHovered
                              ? Color(hex: effectiveColor).opacity(0.18)
                              : Color(hex: "#0E0F11"))
                    Capsule()
                        .stroke(Color(hex: effectiveColor).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                    HStack(spacing: 0) {
                        MiniBotCanvasView(task: task)
                            .frame(width: 22 / 0.6, height: 22 / 0.6)
                            .frame(width: 22, height: 22, alignment: .center)
                            .padding(.leading, 8)
                        Spacer()
                    }
                    Text(displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isHovered
                                         ? Color(hex: effectiveColor).lighter(by: 0.3)
                                         : Color(hex: "#6B7079"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .shadow(color: Color(hex: effectiveColor).opacity(isHovered ? 0.35 : 0), radius: 10, x: 0, y: 2)

                // Alert badge (approval / finished / error)
                if let badge = task.pillBadge {
                    PillBadgeView(badge: badge, taskColor: effectiveColor)
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .onHover { newHover in
            guard !swapping else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}

struct PillBadgeView: View {
    let badge: PillBadge
    let taskColor: String

    private var badgeColor: Color {
        switch badge {
        case .approval: return Color(hex: "#F5A524")
        case .finished: return Color(hex: "#22C55E")
        case .error:    return Color(hex: "#F4505E")
        }
    }

    private var icon: String {
        switch badge {
        case .approval: return "exclamationmark"
        case .finished: return "checkmark"
        case .error:    return "xmark"
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#0B0C0E"))
                .frame(width: 14, height: 14)
            Circle()
                .fill(badgeColor)
                .frame(width: 12, height: 12)
            Image(systemName: icon)
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.black)
        }
        .shadow(color: badgeColor.opacity(0.6), radius: 4, x: 0, y: 0)
    }
}

// MARK: - Column agents (right side of non-overview views)

struct ColumnAgentsView: View {
    @ObservedObject var state: AppState

    var others: [AgentTask] {
        state.tasks.filter { $0.id != state.focusId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(others.prefix(4).enumerated()), id: \.1.id) { idx, task in
                MiniBotCanvasView(task: task)
                    .frame(width: 16 / 0.6, height: 16 / 0.6)
                    .frame(width: 16, height: 16)
                    .position(x: 0, y: CGFloat(50 + idx * 24))
                    .animation(.spring(response: 0.5, dampingFraction: 0.72).delay(Double(idx) * 0.035), value: idx)
            }
        }
    }
}

// MARK: - Card background

struct CardBackground<Content: View>: View {
    /// The wash takes the colour of a state (StateColor), like Klay's glow and badge.
    enum Wash { case error, finished, dizzy, approval, question, searching, soft }

    let wash: Wash?
    let content: (() -> Content)?

    init(wash: Wash?, @ViewBuilder content: @escaping () -> Content) {
        self.wash = wash
        self.content = content
    }

    var washColor: Color {
        switch wash {
        case .error:     return Color(cgColor: StateColor.error).opacity(0.55)
        case .finished:  return Color(cgColor: StateColor.finished).opacity(0.5)
        case .dizzy:     return Color(cgColor: StateColor.dizzy).opacity(0.55)
        case .approval:  return Color(cgColor: StateColor.approval).opacity(0.42)
        case .question:  return Color(cgColor: StateColor.question).opacity(0.38)
        case .searching: return Color(cgColor: StateColor.searching).opacity(0.5)
        case .soft:      return Color.white.opacity(0.08)
        case nil:        return Color.clear
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#141518"))
                .overlay(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: washColor, location: 0),
                            .init(color: .clear, location: 0.7)
                        ]),
                        center: UnitPoint(x: 0.5, y: 1.3),
                        startRadius: 0,
                        endRadius: 280
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.035), lineWidth: 1)
                )

            if let content = content {
                content()
            }
        }
    }
}

extension CardBackground where Content == EmptyView {
    init(wash: Wash?) {
        self.wash = wash
        self.content = nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#141518"))
                .overlay(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: washColor, location: 0),
                            .init(color: .clear, location: 0.7)
                        ]),
                        center: UnitPoint(x: 0.5, y: 1.3),
                        startRadius: 0,
                        endRadius: 280
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.035), lineWidth: 1)
                )
        }
    }
}

// MARK: - Shared sub-components

struct AgentWho: View {
    let task: AgentTask?
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            if let task = task {
                Circle().fill(Color(hex: task.color)).frame(width: 8, height: 8)
                Text(task.name).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            }
            Text(LocalizedStringKey(label)).font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
        }
    }
}

struct CodeBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundColor(Color(hex: "#E8E9EC"))
    }
}

struct ContextChip: View {
    let context: PromptContext
    @State private var glowing = false

    var label: String {
        switch context {
        case .window(let app, _, let url):
            if let url = url, let host = URL(string: url)?.host { return "\(app) · \(host)" }
            return app
        case .file(let name, _): return name
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: "#FF6B5B"), Color(hex: "#F7B32B"), Color(hex: "#2DD4A7"), Color(hex: "#38BDF8"), Color(hex: "#A78BFA")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(Color(hex: "#F1F2F4"))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(glowing ? 0.75 : 0), lineWidth: 1.5))
        .scaleEffect(glowing ? 1.06 : 1.0)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { glowing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeOut(duration: 0.3)) { glowing = false }
            }
        }
    }
}

struct MailField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: "#80858E"))
                .frame(width: 44, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: "#F5F6F8"))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ShimmeringText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#7c818a"), location: 0),
                        .init(color: .white, location: 0.4),
                        .init(color: Color(hex: "#7c818a"), location: 0.7)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

struct ShimmerOverlay: View {
    @State private var phase: CGFloat = 0.0

    var body: some View {
        LinearGradient(
            stops: [
                // Clamp all locations to [0,1] and keep them ordered
                .init(color: .clear,                   location: max(0, phase - 0.3)),
                .init(color: Color.white.opacity(0.6), location: max(0, min(1, phase))),
                .init(color: .clear,                   location: min(1, phase + 0.3))
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .blendMode(.overlay)
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                phase = 1.3  // travels left→right, exits right edge cleanly
            }
        }
    }
}

// MARK: - Button styles

struct PrimaryButton: View {
    let title: String
    let verbatim: Bool
    let kbd: String?
    let action: () -> Void

    init(_ title: String, kbd: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.verbatim = false; self.kbd = kbd; self.action = action
    }

    init(verbatim title: String, kbd: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.verbatim = true; self.kbd = kbd; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Group {
                    if verbatim { Text(verbatim: title) } else { Text(LocalizedStringKey(title)) }
                }.font(.system(size: 12.5, weight: .medium))
                if let k = kbd {
                    Text(k).font(.system(size: 10.5))
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.4)))
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Color(hex: "#F5F6F8"))
            .foregroundColor(Color(hex: "#0B0C0E"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    let verbatim: Bool
    let kbd: String?
    let action: () -> Void

    init(_ title: String, kbd: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.verbatim = false; self.kbd = kbd; self.action = action
    }

    init(verbatim title: String, kbd: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.verbatim = true; self.kbd = kbd; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Group {
                    if verbatim { Text(verbatim: title) } else { Text(LocalizedStringKey(title)) }
                }.font(.system(size: 12.5, weight: .medium))
                if let k = kbd {
                    Text(k).font(.system(size: 10.5))
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.4)))
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Color.white.opacity(0.09))
            .foregroundColor(Color(hex: "#F1F2F4"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.08))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct SendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(Color(hex: "#F5F6F8"))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

// MARK: - Settings island view (Point 7)

struct SettingsIslandView: View {
    @ObservedObject var state: AppState

    private var claudeConnected: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any],
              let ss = hooks["SessionStart"] as? [[String: Any]] else { return false }
        return ss.contains { matcher in
            (matcher["hooks"] as? [[String: Any]])?.contains {
                ($0["command"] as? String)?.contains("NotchBuddy") == true
            } ?? false
        }
    }

    private var apiConnected: Bool {
        KeychainStore.shared.get("anthropic-api-key") != nil
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 10) {
                // Sound row
                HStack(spacing: 10) {
                    Toggle("", isOn: $state.soundEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.75)
                        .frame(width: 44)
                    Text("Sound")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Slider(value: $state.soundVolume, in: 0...0.2)
                        .frame(width: 72)
                        .opacity(state.soundEnabled ? 1 : 0.4)
                }

                // Auto-close row
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .frame(width: 16)
                    Text(String(format: String(localized: "Auto-close · %llds"), Int64(state.autoCloseInterval)))
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach([10, 15, 30], id: \.self) { s in
                            Button("\(s)s") {
                                state.autoCloseInterval = Double(s)
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(state.autoCloseInterval == Double(s) ? Color(hex: "#252830") : Color.clear)
                            .foregroundColor(state.autoCloseInterval == Double(s) ? Color(hex: "#F5F6F8") : Color(hex: "#6B7079"))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Connection status
                HStack(spacing: 14) {
                    StatusBadge(label: "Claude Code", ok: claudeConnected)
                    StatusBadge(label: "API", ok: apiConnected)
                    Spacer()
                    Button("Settings…") {
                        NotificationCenter.default.post(name: .openFullSettings, object: nil)
                    }
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
    }
}

struct StatusBadge: View {
    let label: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ok ? Color(hex: "#22C55E") : Color(hex: "#F4505E"))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
        }
    }
}

// MARK: - Color extension (lighten)

extension Color {
    func lighter(by amount: Double) -> Color {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(
            red: min(1, Double(components.redComponent) + amount),
            green: min(1, Double(components.greenComponent) + amount),
            blue: min(1, Double(components.blueComponent) + amount)
        )
    }
}
