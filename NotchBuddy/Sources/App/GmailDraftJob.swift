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
// missing Gmail connector, a failure, or a call to any other tool, which stops the process at
// once. 90 s at most, then the process is stopped (SIGTERM, then SIGKILL). Nothing is ever sent:
// the user reviews the draft and sends it from Gmail.

@MainActor
final class GmailDraftJob {
    typealias Outcome = GmailDraftOutcome

    /// Same words as the chat's notice.
    static let missingMessage = "Claude Code n'est pas installé sur ce Mac."
    static let folderError = "Impossible de préparer le dossier du brouillon."

    /// The run in progress. One at a time: a new run, or the app quitting, stops it.
    private static var current: GmailDraftJob?

    private let process = ClaudeProcess()
    private var parser = ClaudeStreamParser()
    private var answer = GmailDraftAnswer()
    private var timeLimit: DispatchWorkItem?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var finished = false

    private init() {}

    /// Prepares one draft and returns how it ended. Never sends anything.
    static func run(to: [String], subject: String, intent: String, fileName: String?) async -> Outcome {
        guard let binary = await ChatSession.shared.locateBinary() else {
            ChatSession.shared.claudeCodeIsMissing()
            return .failed(missingMessage)
        }
        current?.finish(.failed(GmailDraftAnswer.stoppedMessage), atQuit: false)
        guard let folder = emptyFolder() else { return .failed(folderError) }
        let request = GmailDraftRequest(to: to, subject: subject, intent: intent, fileName: fileName)
        let job = GmailDraftJob()
        current = job
        return await withCheckedContinuation { continuation in
            job.start(binary: binary, folder: folder, request: request, continuation: continuation)
        }
    }

    /// The app quits: a draft in progress does not outlive the island.
    static func stop() {
        current?.finish(.failed(GmailDraftAnswer.stoppedMessage), atQuit: true)
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
                environment: ChatSession.environment(for: binary),
                directory: folder,
                onOutput: { [self] data in
                    Self.onMain { self.received(data) }
                },
                onOutputEnd: { [self] in
                    Self.onMain { self.outputEnded() }
                },
                onExit: { [self] _ in
                    Self.onMain { self.exited() }
                })
        } catch {
            // Same reading as the chat: a binary that does not start is a missing Claude Code.
            ChatSession.shared.claudeCodeIsMissing()
            finish(.failed(Self.missingMessage), atQuit: false)
            return
        }
        process.write(request.stdinText)
        process.closeInput()

        let limit = DispatchWorkItem { [self] in
            MainActor.assumeIsolated { self.timedOut() }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            MainActor.assumeIsolated { self.processEnded() }
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

    private init() {}

    /// « Préparer le brouillon » is offered: valid addresses and something to say.
    var canPrepare: Bool { GmailDraftRequest.canPrepare(to: to, intent: intent) }

    /// « Préparer un email » for a dropped file: an empty form. A run in progress is kept.
    func startOver() {
        guard phase != .working else { return }
        phase = .editing
        file = nil
        to = ""
        subject = ""
        intent = ""
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
        phase = .working
        state.stateOverride = .thinking

        Task {
            var outcome: GmailDraftOutcome?
            if await ChatSession.shared.availability() == .ready {
                outcome = await GmailDraftJob.run(to: recipients, subject: subject, intent: intent,
                                                  fileName: dropped?.name)
            }
            if state.stateOverride == .thinking { state.stateOverride = nil }
            guard let outcome else {
                phase = .editing
                return
            }
            phase = .done(outcome)
            if case .ready = outcome {
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
            }
        }
    }
}
