import Foundation
import Combine

// MARK: - The Gmail draft, through the user's own Claude Code (Task 15)
//
// « Préparer un email » on a dropped file: Klay writes a short email from what the user wants to
// say and creates a draft in their Gmail, through the Gmail connector of their Claude account.
// One short `claude -p` per draft (`ClaudeCLI.draftArguments`: Haiku, the Gmail draft tool alone,
// no hook, nothing saved), started in an empty folder of its own so that no settings file applies
// (`--setting-sources local`). The request is written on stdin, then stdin is closed.
//
// What the run's events mean is decided by `GmailDraftAnswer` (Foundation, tested): a draft, a
// missing Gmail connector, a failure, a call to any other tool or a draft call that does not match
// the request, which stop the process at once. 90 s at most, then the process is stopped
// (SIGTERM, then SIGKILL). « Annuler » stops it too. Nothing is ever sent: the user reviews the
// draft and sends it from Gmail.
//
// The process's callbacks hold the job weakly: `current` keeps it alive until it finishes, then
// the job, its process and its pipes go.

@MainActor
final class GmailDraftJob {
    typealias Outcome = GmailDraftOutcome

    /// Same words as the chat's notice.
    static let missingMessage = "Claude Code n'est pas installé sur ce Mac."
    static let folderError = "Impossible de préparer le dossier du brouillon."
    static let cancelledMessage = "Préparation annulée."

    /// The run in progress. One at a time: a new run, or the app quitting, stops it.
    private static var current: GmailDraftJob?

    private let process = ClaudeProcess()
    private var parser = ClaudeStreamParser()
    private var answer: GmailDraftAnswer
    private var timeLimit: DispatchWorkItem?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var finished = false

    /// The draft calls are checked against the recipients the user typed.
    private init(request: GmailDraftRequest) {
        answer = GmailDraftAnswer(requestedTo: request.to)
    }

    /// Prepares one draft and returns how it ended. Never sends anything. `stillWanted` is asked
    /// once Claude Code is found: when the binary moved, the lookup goes through a login shell (up
    /// to 3 s), and « Annuler » in that time finds no job to stop.
    static func run(to: [String], subject: String, intent: String, fileName: String?,
                    stillWanted: () -> Bool = { true }) async -> Outcome {
        guard let binary = await ChatSession.shared.locateBinary() else {
            ChatSession.shared.claudeCodeIsMissing()
            return .failed(missingMessage)
        }
        // Cancelled while Claude Code was looked for: no process starts, no draft lands in Gmail.
        guard stillWanted() else { return .failed(cancelledMessage) }
        current?.finish(.failed(GmailDraftAnswer.stoppedMessage), atQuit: false)
        guard let folder = emptyFolder() else { return .failed(folderError) }
        let request = GmailDraftRequest(to: to, subject: subject, intent: intent, fileName: fileName)
        let job = GmailDraftJob(request: request)
        current = job
        return await withCheckedContinuation { continuation in
            job.start(binary: binary, folder: folder, request: request, continuation: continuation)
        }
    }

    /// The app quits: a draft in progress does not outlive the island.
    static func stop() {
        current?.finish(.failed(GmailDraftAnswer.stoppedMessage), atQuit: true)
    }

    /// « Annuler » while Klay prepares the draft: the process is stopped (SIGTERM, then SIGKILL)
    /// and the run returns at once. A draft the connector already made stays in Gmail, unsent.
    static func cancel() {
        current?.finish(.failed(cancelledMessage), atQuit: false)
    }

    /// `draft` in the island's support folder, emptied and created again for each run: never a
    /// project folder, and no `.claude/settings.local.json` that `--setting-sources local` would read.
    private static func emptyFolder() -> URL? {
        let folder = HookServer.supportDir.appendingPathComponent("draft", isDirectory: true)
        let files = FileManager.default
        try? files.removeItem(at: folder)
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return folder
    }

    private func start(binary: String, folder: URL, request: GmailDraftRequest,
                       continuation: CheckedContinuation<Outcome, Never>) {
        self.continuation = continuation
        let prompt = ClaudeCLI.draftSystemPrompt(firstName: resolveUserFirstName())
        do {
            try process.start(
                binary: binary,
                arguments: ClaudeCLI.draftArguments(systemPrompt: prompt),
                // MCP tool search off: the Gmail draft tool is loaded upfront.
                environment: ClaudeCLI.draftEnvironment(from: ProcessInfo.processInfo.environment, binary: binary),
                directory: folder,
                // Weak: the process keeps its handlers after it ends; the job must not live as long.
                onOutput: { [weak self] data in
                    guard let job = self else { return }
                    Self.onMain { job.received(data) }
                },
                onOutputEnd: { [weak self] in
                    guard let job = self else { return }
                    Self.onMain { job.outputEnded() }
                },
                onExit: { [weak self] _ in
                    guard let job = self else { return }
                    Self.onMain { job.exited() }
                })
        } catch {
            // Same reading as the chat: a binary that does not start is a missing Claude Code.
            ChatSession.shared.claudeCodeIsMissing()
            finish(.failed(Self.missingMessage), atQuit: false)
            return
        }
        process.write(request.stdinText)
        process.closeInput()

        let limit = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.timedOut() }
        }
        timeLimit = limit
        DispatchQueue.main.asyncAfter(deadline: .now() + ClaudeCLI.draftTimeLimit, execute: limit)
    }

    /// Runs `body` on the main actor, in the order the calls were made (FIFO main queue): the end
    /// of the output is seen after the last piece of it.
    nonisolated private static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { body() }
        }
    }

    /// One read of stdout. As soon as the run is decided (a draft, or a call to another tool),
    /// the process is stopped.
    private func received(_ data: Data) {
        guard !finished else { return }
        answer.read(parser.feed(data))
        if let end = answer.end { finish(end, atQuit: false) }
    }

    /// stdout closed: everything the process wrote has been read.
    private func outputEnded() {
        processEnded()
    }

    /// The process exited: its last lines may still be on their way through stdout, which gets a
    /// second to come first.
    private func exited() {
        guard !finished else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated { self?.processEnded() }
        }
    }

    private func processEnded() {
        guard !finished else { return }
        answer.processEnded(lastErrorLine: process.lastErrorLine)
        finish(answer.end ?? .failed(GmailDraftAnswer.stoppedMessage), atQuit: false)
    }

    private func timedOut() {
        guard !finished else { return }
        answer.timedOut()
        finish(answer.end ?? .failed(GmailDraftAnswer.timeoutMessage), atQuit: false)
    }

    /// Ends the run once: the time limit is cancelled, the process stopped (a no-op when it is
    /// already gone), and the caller gets the outcome.
    private func finish(_ outcome: Outcome, atQuit: Bool) {
        guard !finished else { return }
        finished = true
        timeLimit?.cancel()
        timeLimit = nil
        process.stop(atQuit: atQuit)
        if Self.current === self { Self.current = nil }
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}

// MARK: - The email card

/// What the email card (MailView) shows. Kept here rather than in the view: the island may fold
/// while Klay prepares the draft, and the result is still there when it opens again.
@MainActor
final class GmailDraftFlow: ObservableObject {
    static let shared = GmailDraftFlow()

    enum Phase: Equatable {
        /// The form: « À », « Objet », « Ce que tu veux dire ».
        case editing
        /// Klay prepares the draft.
        case working
        /// The run is over.
        case done(GmailDraftOutcome)
    }

    @Published private(set) var phase: Phase = .editing
    /// The dropped file the draft is about (« Montrer le fichier »), nil when there is none.
    @Published private(set) var file: URL?
    @Published var to = ""
    @Published var subject = ""
    @Published var intent = ""

    /// The dropped file the form was filled for (name and size: the drop swaps the file for its
    /// copy in the inbox, which keeps both).
    private var formFileKey: String?
    /// Moves on with each run and with « Annuler »: a run that was cancelled changes nothing.
    private var runID = 0

    private init() {}

    private static func fileKey(_ file: DroppedFile?) -> String? {
        guard let file else { return nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? NSNumber)?.int64Value ?? -1
        return "\(file.name)|\(size)"
    }

    /// « Préparer le brouillon » is offered: valid addresses and something to say.
    var canPrepare: Bool { GmailDraftRequest.canPrepare(to: to, intent: intent) }

    /// « Préparer un email » for a dropped file: the form. Still filled for the same file (back
    /// from the Claude Code notice, or after « Annuler »), empty for another one, and empty once a
    /// draft is ready (`GmailDraftOutcome.keepsTheForm`). A run in progress is kept.
    func startOver(for dropped: DroppedFile?) {
        guard phase != .working else { return }
        phase = .editing
        let key = Self.fileKey(dropped)
        guard key != formFileKey else { return }
        formFileKey = key
        file = nil
        to = ""
        subject = ""
        intent = ""
    }

    /// The draft is ready in Gmail: the fields empty and the form belongs to no file, so the same
    /// file opens a blank form. The ready card does not show the fields; `file` stays for
    /// « Montrer le fichier ».
    private func clearForm() {
        formFileKey = nil
        to = ""
        subject = ""
        intent = ""
    }

    /// « Annuler » while Klay prepares the draft: the process stops, and the form comes back as
    /// the user left it.
    func cancel(state: AppState) {
        guard phase == .working else { return }
        runID += 1
        GmailDraftJob.cancel()
        phase = .editing
        if state.stateOverride == .thinking { state.stateOverride = nil }
    }

    /// « Réessayer »: back to the form, as the user left it.
    func edit() {
        guard phase != .working else { return }
        phase = .editing
    }

    /// « Préparer le brouillon »: Klay thinks while the draft is prepared. When Claude Code is
    /// missing or not logged in, the form comes back with the chat's message instead.
    func prepare(state: AppState) {
        guard phase == .editing, canPrepare else { return }
        let recipients = DraftRecipients.split(to)
        let subject = self.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let intent = self.intent.trimmingCharacters(in: .whitespacesAndNewlines)
        let dropped = state.droppedFile.flatMap { FileManager.default.fileExists(atPath: $0.url.path) ? $0 : nil }
        file = dropped?.url
        formFileKey = Self.fileKey(state.droppedFile)
        phase = .working
        // A request card's pose wins (AppState.showsRequestCard); it also drops this one if it
        // comes during the 90 s.
        if !state.showsRequestCard { state.stateOverride = .thinking }
        runID += 1
        let run = runID

        Task {
            var outcome: GmailDraftOutcome?
            if await ChatSession.shared.availability() == .ready {
                // Cancelled while Claude Code was checked: nothing is started.
                guard run == runID else { return }
                // « Annuler » during the binary lookup that `run` may do: nothing is started either.
                outcome = await GmailDraftJob.run(to: recipients, subject: subject, intent: intent,
                                                  fileName: dropped?.name, stillWanted: { run == self.runID })
            }
            // Cancelled: the form is already back.
            guard run == runID else { return }
            if state.stateOverride == .thinking { state.stateOverride = nil }
            guard let outcome else {
                phase = .editing
                return
            }
            phase = .done(outcome)
            if !outcome.keepsTheForm { clearForm() }
            if case .ready = outcome {
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
            }
        }
    }
}
