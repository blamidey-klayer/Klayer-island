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
        case .note:      NoteView(state: state)
        case .settings:  SettingsIslandView(state: state)
        case .greeting:  EmptyView()  // GreetingCanvasView overlaid in IslandRootView
        }
    }
}

// MARK: - Overview

/// The home (lot 6 spec §2), left to right: the rail of icons (Spotify, GitHub, Granola), then one
/// card with Klay at its left and the conversations over the rest, at least 3/4 of the island
/// (`HomeLayout`). GitHub or Spotify in focus: its card takes the list's place.
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

    /// The list (conversations, last choices) shows unless GitHub or Spotify has the focus: their
    /// card replaces it. Any other focus, or none, shows the list.
    private var showsList: Bool {
        !HomeRail.showsCard(focusId: agent?.id)
    }

    var body: some View {
        HStack(spacing: 0) {
            // The rail, on the black island left of the card
            HomeRailView(state: state)
                .frame(width: HomeLayout.rail)
                .frame(maxHeight: .infinity, alignment: .top)

            // The card: Klay at its left (drawn by the island), the list or a service card
            ZStack(alignment: .topLeading) {
                CardBackground(wash: nil)

                if showsList {
                    homeContent
                } else {
                    // GitHub and Spotify cards are drawn for a 98 pt card: they sit, with their ↗
                    // button, in a 98 pt band centred in the taller home card, so they line up with
                    // Klay exactly as on the 160 pt island.
                    ZStack(alignment: .topLeading) {
                        if let agent = agent {
                            IntegrationCardView(task: agent, showingDetail: $showingIntegrationDetail)
                                // Their own drawing, text 108 pt in: moved so it starts where the rows do
                                .padding(.leading, HomeLayout.serviceCardShift)
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
                        .padding(.leading, HomeLayout.serviceCardShift)
                        .frame(height: Self.legacyCardHeight, alignment: .topLeading)
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
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

    /// The list, right of Klay: the running sessions, then the day's finished ones in grey
    /// (`SessionRoster.listed`), then the 3 last choices. What does not fit in the card scrolls
    /// inside it, the card never grows. A permission or a question waiting has its own view.
    /// Hotfix 0.3.5: a plain scroll view, as in 0.3.2. Nothing here reads the scroll view's geometry
    /// or writes state from it, nothing sets its offset, no margins, no snapping, no scroll transition:
    /// 0.3.3 and 0.3.4 crashed on macOS 27 in the scroll view's layout. The wheel of Task 27
    /// (`ListWheel`: the rows near the centre whole, those towards the edges smaller, fainter, slightly
    /// to the right, margins letting the first and the last row reach the centre) waits behind
    /// `HomeLayout.wheelEnabled`, off; `listWheel` and `listWheelMargins` add nothing while it is.
    private var homeContent: some View {
        let sessions = SessionRoster.listed(state.sessions)
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 3) {
                ConversationsView(sessions: sessions, hooksMissing: hooksMissing)
                if !state.recentChoices.isEmpty {
                    ChoiceHistoryView(choices: state.recentChoices)
                        .padding(.top, 4)
                        .listWheel()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // Room for the rows' hover background, 4 pt past each side
            .padding(.horizontal, 4)
        }
        // Wheel only (off): without a session, the empty line and the choices stay at the top.
        .listWheelMargins(sessions.isEmpty ? 0 : ListWheel.homeMargin)
        .scrollBounceBehavior(.basedOnSize)
        // The list's height, `ListWheel.homeListHeight`: change both together.
        .padding(.top, 9)
        .padding(.bottom, 8)
        // The rows start at the list's left edge (`HomeLayout.listStartX`), 12 pt from the card's right
        .padding(.leading, HomeLayout.klay - 4)
        .padding(.trailing, 12 - 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The card shrinks to the 98 pt frame of an inactive view while it fades out
        .clipped()
    }

    /// When the home shows (the island opens, or comes back to it): the roster is pruned, not on a
    /// timer, so a session that ended without telling (no hook since) or finished before midnight
    /// is gone before the user reads the list; and the hooks are checked once, for the hint under
    /// an empty list.
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

// MARK: - Home rail

/// The rail of the home (lot 6 spec §2): Spotify (its pill on), GitHub (its pill on and a token
/// set), Granola (always), greyed like the Granola button of the compact island. A click on Spotify
/// or GitHub shows its card in place of the list; a second click, or the house tab, brings the
/// list back. Granola opens a new note. The rail keeps its width whatever it shows.
private struct HomeRailView: View {
    @ObservedObject var state: AppState
    /// Spotify playing tints its icon (the old pill's Klay danced).
    @ObservedObject private var spotify = SpotifyController.shared

    var body: some View {
        // Rows of 26 pt, 3 apart, as the conversations: the first icon faces the first row
        VStack(spacing: 3) {
            ForEach(state.homeRailIcons, id: \.self) { icon in
                HomeRailButton(icon: icon, state: state,
                               tint: icon == .spotify && spotify.isPlaying ? SpotifyController.green : nil)
            }
        }
        .padding(.top, 9)
    }
}

private struct HomeRailButton: View {
    let icon: RailIcon
    @ObservedObject var state: AppState
    /// A colour for the resting icon ("#RRGGBB"), nil for the grey.
    let tint: String?
    @State private var isHovered = false

    /// The card of this icon is on screen.
    private var isOn: Bool {
        icon.pillId != nil && state.focusTask?.id == icon.pillId
    }

    private var task: AgentTask? {
        guard let id = icon.pillId else { return nil }
        return state.tasks.first { $0.id == id }
    }

    /// Neutral symbols: the logos of Spotify, GitHub and Granola are theirs and are not reused.
    private var symbol: String {
        switch icon {
        case .spotify: return "music.note"
        case .github:  return "arrow.triangle.pull"
        case .granola: return "mic"
        }
    }

    private var label: Text {
        switch icon {
        case .granola: return Text("Nouvelle note Granola")
        case .spotify, .github:
            if isOn { return Text("Retour aux conversations") }
            return Text(verbatim: icon == .spotify ? "Spotify" : "GitHub")
        }
    }

    private var color: Color {
        if isOn { return Color(hex: "#F5F6F8") }
        if isHovered { return Color(hex: "#B0B5BE") }
        if let tint { return Color(hex: tint).opacity(0.7) }
        return Color(hex: "#8E939C").opacity(0.45)
    }

    var body: some View {
        Button(action: click) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(color)
                .frame(width: HomeLayout.railIconWidth, height: 26)
                .background(
                    isOn ? Color(hex: "#1D1F23") :
                    isHovered ? Color.white.opacity(0.07) : Color.clear
                )
                .clipShape(Capsule())
                .contentShape(Capsule())
                // GitHub's alerts (a CI that failed, a review asked) badge its icon, as they badged its pill
                .overlay(alignment: .topTrailing) {
                    if let badge = task?.pillBadge {
                        PillBadgeView(badge: badge, taskColor: task?.color ?? "#8E939C")
                            .scaleEffect(0.75)
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }

    private func click() {
        switch HomeRail.action(for: icon, focusId: state.focusTask?.id) {
        case .showCard(let pillId):
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.showCard(pillId) }
            SoundEngine.shared.play("blip")
        case .showList:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.showHomeList() }
            SoundEngine.shared.play("blip")
        case .openGranola:
            GranolaLink.open(using: { NSWorkspace.shared.open($0) })
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

/// « Ouvrir cette session », the open button of the finished and error views of a Claude Code session
/// (Task 27), then the island folds. What it opens is `OpenTarget`'s: the VS Code tab of a VS Code
/// extension session, the Claude app for a session of the Claude app, else the app the session runs
/// in (launched when it is not running). `session` is the session the view tells about, nil for the
/// pill in focus (`pillTask`). With nothing known, as before: the pill's terminal or editor, then any
/// known terminal.
private struct SessionOpenButton: View {
    let session: SessionRow?
    let pillTask: AgentTask?

    var body: some View {
        PrimaryButton(OpenTarget.sessionLabel) {
            // The session's own target: its pill may carry another session now.
            let target = session?.openTarget ?? pillTask.flatMap { task in
                OpenTarget.of(source: SessionSource.of(pillId: task.id), entrypoint: nil,
                              hostBundleId: task.id == "integration_claude" ? task.hostApp : nil, sessionId: nil)
            }
            var opened = target.map { SessionOpener.open($0, launching: true) } ?? false
            if !opened {
                opened = TerminalTarget.activate(sessionBundleId: session?.hostBundleId ?? pillTask?.sessionBundleId)
            }
            if !opened {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
            }
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
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
                Text("Laisse-moi souffler : je reprends dans trois secondes.")
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
    // Timer only runs while this is the active tab: killed on deactivation
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
            // The invitation under Klay. Klay is the island's own, placed in the middle of this
            // card by IslandConst.viewLayouts[.upload] (y 92); no second figure here. This view
            // gets the 98 pt content frame (island y 55 to 153): the text's centre sits 78 pt
            // down, at island y 133, where the drag-over canvas draws it (USC.TEXT_Y).
            Text("Dépose ton fichier")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(state.fileDragOver ? Color(hex: "#34D399") : Color(hex: "#D5D7DB"))
                .frame(height: 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 12)
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
        // 20 fps: smooth enough for slow dash, 3× lighter than 60fps
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0/20.0, repeats: true) { _ in
            // Scheduled from the view on the main run loop: each tick runs on the main thread,
            // where the view's state may change.
            MainActor.assumeIsolated {
                dashPhase  += 1.0          // 20 pt/s march
                breathAngle += 0.9 / 20.0  // advance sin phase at 0.9 rad/s
            }
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
        // TimelineView fires at display refresh rate: progress derived from elapsed wall time,
        // not from @Published uploadProgress (which only flips to 1.0 at completion). Paused while
        // another view is on screen: every view stays in the tree (opacity 0).
        TimelineView(.animation(paused: state.view != .uploading)) { tl in
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

                // Permanent green radial wash: brighter at completion
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

                // Text row: filename + % (above bar)
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
                    PrimaryButton("Ask a question") {
                        state.askAboutDroppedFile()
                        state.view = .prompt
                    }
                    SecondaryButton("Préparer un email") {
                        GmailDraftFlow.shared.startOver(for: state.droppedFile)
                        state.view = .mail
                    }
                }
            }
            .padding(.leading, 98)
            .padding(.trailing, 18)
        }
    }
}

// MARK: - Mail (a Gmail draft, never sent from the island)

/// « Préparer un email »: the user says what to write, Klay creates a draft in their Gmail through
/// the Gmail connector of their Claude account (GmailDraftJob). Nothing is sent from here: the
/// card opens the draft in Gmail, where the user attaches the file and sends it.
struct MailView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var flow = GmailDraftFlow.shared
    /// Claude Code missing or not logged in: the same notice as the chat.
    @ObservedObject private var chat = ChatSession.shared
    /// « À » has the focus: the address being typed is not flagged yet.
    @FocusState private var editingTo: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: wash)
            content
                .padding(.leading, 92)
                .padding(.trailing, 18)
                .padding(.vertical, 8)
        }
        .onAppear {
            if state.view == .mail { checkClaude() }
        }
        // Every view stays in the tree: the check runs when the card comes on screen.
        .onChange(of: state.view) { _, view in
            if view == .mail { checkClaude() }
        }
    }

    private var wash: CardBackground<EmptyView>.Wash? {
        switch flow.phase {
        case .done(.ready):  return .finished
        case .done(.failed): return .error
        default:             return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch flow.phase {
        case .editing:
            if let notice = unavailableNotice {
                unavailableCard(notice)
            } else {
                form
            }
        case .working:
            VStack(alignment: .leading, spacing: 8) {
                Text("Préparation du brouillon…")
                    .font(.system(size: 14, weight: .semibold))
                SecondaryButton("Annuler") { flow.cancel(state: state) }
            }
        case .done(let outcome):
            result(outcome)
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            MailField(label: "À", placeholder: "adresse@exemple.fr", text: $flow.to, focus: $editingTo)
            if let problem = DraftRecipients.problem(in: flow.to, editing: editingTo) {
                Text(verbatim: problem)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#FF8D97"))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            MailField(label: "Objet", placeholder: "Facultatif", text: $flow.subject)

            // What the email should say: TextEditor scrolls internally when text overflows
            ZStack(alignment: .topLeading) {
                TextEditor(text: $flow.intent)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                if flow.intent.isEmpty {
                    Text("Ce que tu veux dire")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#80858E"))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                PrimaryButton("Préparer le brouillon") { flow.prepare(state: state) }
                    .disabled(!flow.canPrepare)
                    .opacity(flow.canPrepare ? 1 : 0.4)
                SecondaryButton("Annuler") { state.view = .choose }
                if let name = state.droppedFile?.name {
                    Text(String(format: String(localized: "mail.with %@"), name))
                        .font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }

    // MARK: Claude Code missing or not logged in

    /// The chat's words, from the last check.
    private var unavailableNotice: LocalizedStringKey? {
        switch chat.knownAvailability {
        case .missingCLI?:  return "Claude Code n'est pas installé sur ce Mac."
        case .notLoggedIn?: return "Connecte Claude Code : ouvre un terminal, lance claude puis /login."
        default:            return nil
        }
    }

    private func unavailableCard(_ notice: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(notice)
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: "#9398A1"))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if chat.knownAvailability == .missingCLI {
                    SecondaryButton("Installer Claude Code") {
                        NSWorkspace.shared.open(ClaudeCLI.installURL)
                    }
                }
                SecondaryButton("Annuler") { state.view = .choose }
            }
        }
    }

    private func checkClaude() {
        Task { _ = await ChatSession.shared.availability() }
    }

    // MARK: Result

    @ViewBuilder
    private func result(_ outcome: GmailDraftOutcome) -> some View {
        switch outcome {
        case .ready(let draft, let preview):
            readyCard(draft, preview: preview)
        case .gmailMissing:
            retryCard(Text("Gmail n'est pas connecté à ton compte Claude. Ajoute le connecteur Gmail sur claude.ai, puis réessaie."))
        case .failed(let message):
            retryCard(Text(verbatim: message))
        }
    }

    private func readyCard(_ draft: GmailDraft, preview: GmailDraftPreview?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Brouillon prêt dans Gmail")
                .font(.system(size: 14, weight: .semibold))
            if let preview {
                if !preview.subject.isEmpty {
                    Text(verbatim: preview.subject)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1).truncationMode(.tail)
                }
                ForEach(Array(preview.firstLines().enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            if flow.file != nil {
                Text("Glisse le fichier dans le brouillon pour le joindre.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            HStack(spacing: 8) {
                PrimaryButton("Ouvrir dans Gmail") {
                    // GmailDraft.parse only keeps https://mail.google.com links.
                    NSWorkspace.shared.open(draft.viewURL)
                }
                if let file = flow.file {
                    SecondaryButton("Montrer le fichier") {
                        NSWorkspace.shared.activateFileViewerSelecting([file])
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func retryCard(_ message: Text) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            message
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
            SecondaryButton("Réessayer") { flow.edit() }
        }
    }
}

// MARK: - Prompt (chat)

struct PromptView: View {
    @ObservedObject var state: AppState
    /// The chat runs through the Claude Code installed on the Mac (ChatSession).
    @ObservedObject private var chat = ChatSession.shared
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
                                if state.stateOverride == .thinking {
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
                            if v == .thinking {
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

                if let notice = unavailableNotice {
                    // Claude Code missing or not logged in: what to do, in place of the field.
                    VStack(alignment: .leading, spacing: 8) {
                        Text(notice)
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(hex: "#9398A1"))
                            .fixedSize(horizontal: false, vertical: true)
                        if chat.knownAvailability == .missingCLI {
                            SecondaryButton("Installer Claude Code") {
                                NSWorkspace.shared.open(ClaudeCLI.installURL)
                            }
                        }
                    }
                } else {
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
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .padding(.bottom, 10)
        .onAppear {
            focused = true
            if state.view == .prompt { checkChat() }
        }
        // Every view stays in the tree: the check runs when the chat comes on screen.
        .onChange(of: state.view) { _, view in
            if view == .prompt { checkChat() }
        }
        .onChange(of: chat.isAnswering) { _, answering in
            if !answering && state.view == .prompt { focused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandSendMessage)) { _ in
            guard state.view == .prompt else { return }
            sendMessage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandNewConversation)) { _ in
            guard state.view == .prompt else { return }
            text = ""
            state.chatHistory = []
            ChatSession.shared.reset()
            focused = true
        }
    }

    /// Claude Code missing or not logged in, as the last check found it.
    private var unavailableNotice: LocalizedStringKey? {
        switch chat.knownAvailability {
        case .missingCLI?:  return "Claude Code n'est pas installé sur ce Mac."
        case .notLoggedIn?: return "Connecte Claude Code : ouvre un terminal, lance claude puis /login."
        default:            return nil
        }
    }

    private func checkChat() {
        Task { _ = await ChatSession.shared.availability() }
    }

    private func sendMessage() {
        dictation.stop()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // One answer at a time: what is typed during an answer stays in the field.
        guard !query.isEmpty, unavailableNotice == nil, !chat.isAnswering else { return }
        text = ""
        focused = false
        var file: URL?
        if case .file(_, let url)? = state.promptContext { file = url }
        ChatSession.shared.send(query, attachment: file, context: state.promptContext, into: state)
    }
}


// MARK: - Chip flow layout

/// Wrapping horizontal flow layout: used by QuestionView.
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

// MARK: - Note (short message, auto-closes)

struct NoteView: View {
    @ObservedObject var state: AppState

    /// The colour of a Claude app note's icon, from its sound: a permission, Claude waiting, a
    /// finished answer (the colours of Klay's states, as on the rows).
    static func color(ofSound sound: String) -> Color {
        switch sound {
        case "approval": return StateColor.color(of: .approval)
        case "finish":   return StateColor.color(of: .finished)
        default:         return StateColor.color(of: .question)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            if let alert = state.claudeAppAlert {
                // The Claude app waits for the user (AppState.showClaudeAppAlert): the note holds
                // until the pointer has been on the island and left, like a finished session's. Its
                // source icon before the title (Task 27): `</>` for a Code tab session, the Claude mark
                // for Chat and Cowork, in the colour of what it says.
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        SourceIconView(icon: alert.source.icon, color: Self.color(ofSound: alert.sound))
                        Text(alert.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(alert.message)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 8) {
                        // « Ouvrir ce chat » (Chat, Cowork) or « Ouvrir cette session » (Code tab): the
                        // Claude app comes forward; no link to a given conversation is documented.
                        PrimaryButton(alert.source.openLabel) {
                            SessionOpener.openClaudeApp()
                            NotificationCenter.default.post(name: .islandCollapse, object: nil)
                        }
                        SecondaryButton("OK") {
                            NotificationCenter.default.post(name: .islandCollapse, object: nil)
                        }
                    }
                }
                .padding(.leading, 98)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.noteMessage ?? "")
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.leading, 98)
            }
        }
    }
}

// MARK: - Integration card (the home's card in place of the list when GitHub or Spotify is focused)

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
            // Idle / not connected view: slides in from left when returning from detail
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
                    // No stats yet but activity loaded: show mini-row only
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

// MARK: - Pill badge (the home's rail icons)

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
                // A session's name can run to 120 characters: one line, cut with « … », the label kept whole.
                Text(task.name).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(LocalizedStringKey(label)).font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
                .lineLimit(1)
                .fixedSize()
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
    /// Follows the field's focus, when the caller needs it.
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: "#80858E"))
                .frame(width: 44, alignment: .leading)
            field
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: "#F5F6F8"))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var field: some View {
        if let focus {
            TextField(placeholder, text: $text).focused(focus)
        } else {
            TextField(placeholder, text: $text)
        }
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

    /// Klayer Island's own hooks in ~/.claude/settings.json (`HookServer.claudeHooksInstalled()`),
    /// read when this view comes on screen, never on each render: the view stays in the tree
    /// while another one shows.
    @State private var claudeConnected = false
    /// The quick chat's Claude Code (installed, logged in with claude.ai), as last checked.
    @ObservedObject private var chat = ChatSession.shared

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
                    StatusBadge(label: "Chat", ok: chat.knownAvailability == .ready)
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
        .onAppear { if state.view == .settings { refreshStatus() } }
        .onChange(of: state.view) { _, view in
            if view == .settings { refreshStatus() }
        }
    }

    private func refreshStatus() {
        claudeConnected = HookServer.claudeHooksInstalled()
        Task { _ = await ChatSession.shared.availability() }
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
