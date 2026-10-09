import Foundation
import Combine

// MARK: - The quick chat, through the user's own Claude Code (Task 14)
//
// One long-lived `claude -p` process per conversation (`ClaudeCLI.chatArguments`: Haiku, no
// tool, no hook, nothing saved), started on the first message. Each message is one
// `stream-json` line on its stdin; the answer streams back on stdout, read by a
// reading thread into a `ClaudeStreamParser` and written into `AppState.chatHistory` on
// the main actor. The island stores no key and no token: Claude Code uses the user's own
// claude.ai login.
//
// Lifecycle: the process waits on stdin between messages (it costs nothing) and is stopped
// after 10 minutes without a message (one DispatchWorkItem, rescheduled at each message and at
// each answer's end), on « Nouvelle conversation » (`reset`) and when the app quits (`stop`).
// Every stop moves `ChatTurnToken` to a new generation, and every callback of a process carries
// the generation it was started in: the tail of an answer from a stopped process is dropped,
// never written into the next conversation. What an answer's events mean is decided by
// `ChatAnswer` (Foundation, tested), including the tool tripwire: a process that shows a tool is
// stopped.

@MainActor
final class ChatSession: ObservableObject {
    static let shared = ChatSession()

    typealias Availability = ChatAvailability

    /// What the last check found, nil before the first one. The chat view shows the install or
    /// login message from it.
    @Published private(set) var knownAvailability: Availability?
    /// From a message until the end of its answer. One answer at a time.
    @Published private(set) var isAnswering = false

    /// The answer being written: its generation, its bubble, the state that holds it, and
    /// what its events said so far.
    private struct Turn {
        let generation: Int
        let bubbleID: UUID
        let state: AppState
        var answer = ChatAnswer()
    }

    private var token = ChatTurnToken()
    private var process: ClaudeProcess?
    private var parser = ClaudeStreamParser()
    private var turn: Turn?
    /// The window or file already sent to the live process, so it goes once.
    private var sentContextKey: String?
    /// The live process has had a message: the earlier exchanges go only with the first one.
    private var processHasMessages = false
    /// The dropped file being read, cancelled by a reset (a PDF stops between two pages).
    private var attachmentLoad: Task<ChatAttachment.Outcome, Never>?
    private var idleStop: DispatchWorkItem?

    /// Where `claude` is: kept while it stays executable.
    private var binaryPath: String?
    /// The login shell lookup, run once for the app's life.
    private var shellLookup: Task<String?, Never>?
    private var availabilityCheck: Task<Availability, Never>?

    private let systemPrompt = ClaudeCLI.chatSystemPrompt(firstName: resolveUserFirstName())

    static let genericError = "Claude Code s'est arrêté pendant la réponse."
    static let noAnswer = "Claude Code n'a pas répondu."
    static let folderError = "Impossible de préparer le dossier du chat."

    private init() {}

    // MARK: - Availability

    /// Whether the chat can run: `claude` found and logged in with claude.ai. The answer is
    /// kept once the chat is ready; a missing or logged-out Claude Code is asked again the next
    /// time the chat opens, so installing or logging in needs no relaunch of the island. Off the
    /// main thread, 5 s at most.
    func availability() async -> Availability {
        if knownAvailability == .ready { return .ready }
        if let check = availabilityCheck { return await check.value }
        let check = Task { await self.checkAvailability() }
        availabilityCheck = check
        let result = await check.value
        availabilityCheck = nil
        return result
    }

    private func checkAvailability() async -> Availability {
        guard let binary = await locateBinary() else {
            knownAvailability = .missingCLI
            return .missingCLI
        }
        let outcome = await ShortRun.run(binary, ClaudeCLI.authStatusArguments,
                                         environment: Self.environment(for: binary),
                                         directory: nil, timeout: ClaudeCLI.authStatusTimeout)
        // Timed out: unknown, not kept. The chat is tried and a failed turn says why.
        guard let result = ClaudeCLI.availability(afterAuthStatus: outcome) else {
            return knownAvailability ?? .ready
        }
        if result == .missingCLI { binaryPath = nil }
        knownAvailability = result
        return result
    }

    /// The `claude` binary: the usual install folders first, then once for the app's life a
    /// login shell (`command -v claude`, 3 s at most, off the main thread). The Gmail draft
    /// (GmailDraftJob) finds Claude Code here too.
    func locateBinary() async -> String? {
        let files = FileManager.default
        if let path = binaryPath, files.isExecutableFile(atPath: path) { return path }
        binaryPath = ClaudeCLI.locate(home: NSHomeDirectory(), isExecutable: { files.isExecutableFile(atPath: $0) })
        if let path = binaryPath { return path }

        let lookup: Task<String?, Never>
        if let running = shellLookup {
            lookup = running
        } else {
            lookup = Task { await Self.lookUpInLoginShell() }
            shellLookup = lookup
        }
        guard let found = await lookup.value, FileManager.default.isExecutableFile(atPath: found) else { return nil }
        binaryPath = found
        return found
    }

    nonisolated private static func lookUpInLoginShell() async -> String? {
        let outcome = await ShortRun.run("/bin/zsh", ClaudeCLI.shellLookupArguments, environment: nil,
                                         directory: nil, timeout: ClaudeCLI.shellLookupTimeout)
        guard case .finished(let status, let output) = outcome, status == 0 else { return nil }
        return ClaudeCLI.shellLookupPath(output: String(decoding: output, as: UTF8.self),
                                         isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    /// The environment of `claude auth status`. The chat and the draft add their own switches
    /// (`ClaudeCLI.chatEnvironment`, `ClaudeCLI.draftEnvironment`).
    nonisolated static func environment(for binary: String) -> [String: String] {
        ClaudeCLI.environment(from: ProcessInfo.processInfo.environment, binary: binary)
    }

    // MARK: - Messages

    /// Sends a message of the chat. The user's bubble and an empty answer bubble are added at
    /// once; the answer fills the second one as it streams. `context` (the window or the file
    /// the user attached) goes with the first message that follows it, never twice to the same
    /// process; `attachment` is the dropped file to read for it. Ignored while an answer is
    /// being written.
    func send(_ text: String, attachment: URL?, context: PromptContext?, into state: AppState) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isAnswering else { return }

        var windowLine: String?
        var fileURL = attachment
        switch context {
        case .window(let appName, let title, let url):
            windowLine = ChatOutgoing.windowContext(appName: appName, title: title, url: url)
        case .file(_, let url):
            fileURL = fileURL ?? url
        case nil:
            break
        }
        let contextKey = Self.contextKey(window: windowLine, file: fileURL)

        // What the conversation said so far, for a process that starts on this message.
        let earlier = state.chatHistory.map { (fromUser: $0.role == .user, text: $0.content) }

        state.chatHistory.append(ChatMessage(role: .user, content: query))
        let bubble = ChatMessage(role: .assistant, content: "")
        state.chatHistory.append(bubble)
        // A request card's pose wins (AppState.showsRequestCard); it also drops this one if it
        // comes during the answer.
        if !state.showsRequestCard { state.stateOverride = .thinking }
        isAnswering = true
        let generation = token.generation
        turn = Turn(generation: generation, bubbleID: bubble.id, state: state)
        scheduleIdleStop()

        Task {
            await self.deliver(query, windowLine: windowLine, fileURL: fileURL, contextKey: contextKey,
                               earlier: earlier, generation: generation)
        }
    }

    /// Reads the file if it is due, starts the process if there is none, and writes the line.
    private func deliver(_ query: String, windowLine: String?, fileURL: URL?, contextKey: String?,
                         earlier: [(fromUser: Bool, text: String)], generation: Int) async {
        // A new process has seen nothing: the context goes again. A live one gets it only
        // when it changed since its last message.
        let contextDue = contextKey != nil && (process == nil || contextKey != sentContextKey)

        // The file first: a file that cannot be sent never starts Claude.
        var attachment: ChatAttachment?
        if contextDue, let fileURL {
            let load = Task.detached(priority: .userInitiated) { ChatAttachment.load(url: fileURL) }
            attachmentLoad = load
            let outcome = await load.value
            // After a reset this turn is over and a newer load may be running: leave it alone.
            guard token.accepts(generation) else { return }
            attachmentLoad = nil
            switch outcome {
            case .ready(let built):
                attachment = built
            case .refused(let message):
                refuseAttachment(message, file: fileURL)
                return
            }
        }

        if process == nil {
            guard let binary = await locateBinary() else {
                guard token.accepts(generation) else { return }
                cannotLaunch()
                return
            }
            guard token.accepts(generation) else { return }
            if process == nil {
                guard launch(binary) else { return }
            }
        }
        guard process != nil, token.accepts(generation) else { return }

        let transcript = processHasMessages ? nil : ChatOutgoing.transcript(earlier)
        let outgoing = ChatOutgoing.compose(query: query,
                                            windowContext: contextDue ? windowLine : nil,
                                            attachment: attachment,
                                            transcript: transcript)
        // The line is JSON: with an image, megabytes of base64 to encode. Off the main actor.
        let line = await Task.detached(priority: .userInitiated) { outgoing.line }.value
        // A reset, a crash or the idle stop while it was encoded: that turn is already closed.
        guard let process, token.accepts(generation) else { return }
        if contextDue { sentContextKey = contextKey }
        processHasMessages = true
        process.write(line)
    }

    /// Identifies the attached window or file. A file is known by its name, size and date, so
    /// the copy the drop makes in the inbox is the same file, and a new version is not.
    private static func contextKey(window: String?, file: URL?) -> String? {
        if let file {
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
            let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "file:\(file.lastPathComponent)|\(size)|\(date)"
        }
        return window.map { "window:\($0)" }
    }

    /// Ends the conversation: the process stops and an answer still arriving is dropped. The
    /// caller clears `chatHistory` (« Nouvelle conversation »).
    func reset() {
        endConversation(atQuit: false)
    }

    /// Stops the process for good (the app quits): it is gone before this returns, at most
    /// half a second after SIGTERM.
    func stop() {
        endConversation(atQuit: true)
    }

    private func endConversation(atQuit: Bool) {
        let interrupted = turn
        stopProcess(atQuit: atQuit)
        turn = nil
        isAnswering = false
        if let interrupted {
            removeBubbleIfEmpty(interrupted)
            interrupted.state.stateOverride = nil
        }
    }

    // MARK: - Process

    /// Starts `claude` in an empty folder of its own (no project CLAUDE.md there). False when
    /// it could not start: the turn is closed.
    private func launch(_ binary: String) -> Bool {
        let folder = HookServer.supportDir.appendingPathComponent("chat", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            failTurn(Self.folderError)
            return false
        }

        let generation = token.generation
        let started = ClaudeProcess()
        do {
            try started.start(
                binary: binary,
                arguments: ClaudeCLI.chatArguments(systemPrompt: systemPrompt),
                // No connector, no tool search: the chat process starts no MCP server.
                environment: ClaudeCLI.chatEnvironment(from: ProcessInfo.processInfo.environment, binary: binary),
                directory: folder,
                onOutput: { data in
                    Self.onMain { $0.received(data, generation: generation) }
                },
                onOutputEnd: {
                    Self.onMain { $0.outputEnded(generation: generation) }
                },
                onExit: { _ in
                    Self.onMain { $0.exited(generation: generation) }
                })
        } catch {
            cannotLaunch()
            return false
        }
        process = started
        parser = ClaudeStreamParser()
        sentContextKey = nil
        processHasMessages = false
        return true
    }

    /// Runs `body` on the main actor, in the order the calls were made (FIFO main queue): the
    /// end of the output is seen after the last piece of it.
    nonisolated private static func onMain(_ body: @escaping @MainActor @Sendable (ChatSession) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { body(ChatSession.shared) }
        }
    }

    /// One read of stdout: `ChatAnswer` reads its events, the bubble is written once.
    private func received(_ data: Data, generation: Int) {
        guard token.accepts(generation), process != nil else { return }
        let events = parser.feed(data)
        guard var current = turn, current.generation == generation else {
            // Output between two answers (none is expected): no bubble, but never a tool.
            if events.contains(where: ChatAnswer.breaksNoToolRule) { stopProcess() }
            return
        }
        current.answer.read(events)
        turn = current
        writeBubble(current)
        if let end = current.answer.end { finishTurn(end) }
    }

    /// The answer is over: kept in its bubble, or an error note. A tool seen in the process
    /// stops it.
    private func finishTurn(_ end: ChatAnswer.End) {
        guard let current = turn else { return }
        turn = nil
        isAnswering = false
        switch end {
        case .answered:
            scheduleIdleStop()
            current.state.stateOverride = nil
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        case .failed(let message):
            scheduleIdleStop()
            // The CLI's message is already in French when it is a known error (ChatAnswer); the
            // last stderr line goes through the same words (ClaudeCLI.lastErrorLine).
            showError(current, message: message ?? process?.lastErrorLine ?? Self.genericError)
        case .empty:
            scheduleIdleStop()
            showError(current, message: ChatAnswer.emptyMessage)
        case .toolsOffered:
            stopProcess()
            showError(current, message: ChatAnswer.toolsMessage)
        }
    }

    /// stdout closed: everything the process wrote has been read, the process is over. (This
    /// moves to a new generation, so the exit that follows is not read.)
    private func outputEnded(generation: Int) {
        guard token.accepts(generation), process != nil else { return }
        processEnded(generation: generation)
    }

    /// The process exited before its stdout was seen closed. With no answer in progress it is
    /// over now; during an answer its last lines may still be on their way through stdout, so
    /// the end of stdout gets a second to come first (then this call is stale and ignored).
    private func exited(generation: Int) {
        guard token.accepts(generation), process != nil else { return }
        guard turn != nil else {
            processEnded(generation: generation)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated { ChatSession.shared.processEnded(generation: generation) }
        }
    }

    /// The process is gone on its own (crash, or killed outside the island). An answer in
    /// progress becomes an error note with the last line of stderr; the next message starts a
    /// new process.
    private func processEnded(generation: Int) {
        guard token.accepts(generation), let ended = process else { return }
        let errorLine = ended.lastErrorLine
        let interrupted = turn
        stopProcess()
        guard let interrupted else { return }
        turn = nil
        isAnswering = false
        // Already in French when it is a known error (ClaudeCLI.lastErrorLine).
        showError(interrupted, message: errorLine ?? Self.genericError)
    }

    /// Stops the live process, if any, and moves to a new generation so that nothing it still
    /// sends is read. `atQuit`: the app is quitting, the process is killed before this returns.
    private func stopProcess(atQuit: Bool = false) {
        token.reset()
        idleStop?.cancel()
        idleStop = nil
        attachmentLoad?.cancel()
        attachmentLoad = nil
        process?.stop(atQuit: atQuit)
        process = nil
        parser = ClaudeStreamParser()
        sentContextKey = nil
        processHasMessages = false
    }

    /// 10 minutes after the last message or answer, the process stops. A single work item,
    /// replaced each time: no repeating timer.
    private func scheduleIdleStop() {
        idleStop?.cancel()
        let generation = token.generation
        let work = DispatchWorkItem {
            MainActor.assumeIsolated { ChatSession.shared.idleLimitReached(generation: generation) }
        }
        idleStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ClaudeCLI.chatIdleLimit, execute: work)
    }

    private func idleLimitReached(generation: Int) {
        guard token.accepts(generation) else { return }
        let hung = turn
        stopProcess()
        guard let hung else { return }
        turn = nil
        isAnswering = false
        showError(hung, message: Self.noAnswer)
    }

    // MARK: - Bubbles and notes

    private func writeBubble(_ current: Turn) {
        let history = current.state.chatHistory
        guard let index = history.firstIndex(where: { $0.id == current.bubbleID }),
              history[index].content != current.answer.text else { return }
        current.state.chatHistory[index].content = current.answer.text
    }

    private func removeBubbleIfEmpty(_ current: Turn) {
        current.state.chatHistory.removeAll {
            $0.id == current.bubbleID && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The error note of the chat: Klay in error, the message on the note view. Only from the chat
    /// itself: a permission or question card that came during the answer, or any other view the
    /// user went to, stays on screen, and Klay only stops thinking.
    private func showError(_ current: Turn, message: String) {
        removeBubbleIfEmpty(current)
        let state = current.state
        guard state.view == .prompt else {
            if state.stateOverride == .thinking { state.stateOverride = nil }
            return
        }
        state.stateOverride = .error
        state.noteMessage = message
        state.view = .note
    }

    /// Closes the turn in progress with an error note.
    private func failTurn(_ message: String) {
        guard let current = turn else { return }
        turn = nil
        isAnswering = false
        showError(current, message: message)
    }

    /// Claude Code is not there, or would not start: the chat shows the install message.
    private func cannotLaunch() {
        claudeCodeIsMissing()
        guard let current = turn else { return }
        turn = nil
        isAnswering = false
        removeBubbleIfEmpty(current)
        current.state.stateOverride = nil
    }

    /// Claude Code was not found, or would not start (here or for the Gmail draft): the chat and
    /// the email card show the install message until a later check finds it.
    func claudeCodeIsMissing() {
        binaryPath = nil
        knownAvailability = .missingCLI
    }

    /// The dropped file cannot go to Claude: a note says why, Claude is not started, and the
    /// file leaves the chat (the next messages go without it). Matched by name: while it was
    /// read, the drop may have swapped the context to its copy in the inbox.
    private func refuseAttachment(_ message: String, file: URL) {
        if let current = turn, case .file(let name, let url)? = current.state.promptContext,
           name == file.lastPathComponent || url?.lastPathComponent == file.lastPathComponent {
            current.state.promptContext = nil
        }
        failTurn(message)
    }
}

// MARK: - A `claude` process

/// A `claude` process of the island and its three pipes: the long-lived one of the chat, or the
/// short one of a Gmail draft (GmailDraftJob). Its callbacks run on background threads: they only
/// touch what is immutable here, or `errorTail` behind `lock`.
final class ClaudeProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    /// Writes go through one serial queue: a line with an image is megabytes, and the pipe
    /// only drains as fast as Claude Code reads it, which must never block the main thread.
    private let writer = DispatchQueue(label: "ai.klayer.island.chat.stdin")
    private let lock = NSLock()
    private var errorTail = Data()
    /// Only read and written on `writer`: stdin is closed once.
    private var inputClosed = false

    /// Starts the process. `onOutput` gets each read of stdout, `onOutputEnd` its end, `onExit`
    /// the exit: all on background threads.
    func start(binary: String, arguments: [String], environment: [String: String], directory: URL,
               onOutput: @escaping @Sendable (Data) -> Void,
               onOutputEnd: @escaping @Sendable () -> Void,
               onExit: @escaping @Sendable (Int32) -> Void) throws {
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        process.terminationHandler = { ended in onExit(ended.terminationStatus) }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw error
        }

        // stdout and stderr are each read by a thread of their own, blocked in read(2) until the
        // process writes (no CPU while it waits). At the end of the stream the read end is closed
        // right there: Foundation can keep the handle longer than this object, and its descriptor
        // must not stay open after the run (a dispatch read source would not allow closing it).
        let out = output.fileHandleForReading
        let err = errors.fileHandleForReading
        let reader = Thread {
            while true {
                let data = out.availableData
                if data.isEmpty { break }
                onOutput(data)
            }
            try? out.close()
            onOutputEnd()
        }
        reader.name = "ai.klayer.island.claude.stdout"
        reader.start()
        let errorReader = Thread { [weak self] in
            while true {
                let data = err.availableData
                if data.isEmpty { break }
                self?.keepError(data)
            }
            try? err.close()
        }
        errorReader.name = "ai.klayer.island.claude.stderr"
        errorReader.start()
    }

    /// Writes one line on stdin. A write that fails (the process is gone) is dropped: the end
    /// of the process is reported by `onExit`. The line becomes bytes on `writer` too: with an
    /// image it is megabytes to copy, never on the main thread.
    func write(_ line: String) {
        writer.async { [self] in
            guard !inputClosed else { return }
            try? input.fileHandleForWriting.write(contentsOf: Data(line.utf8))
        }
    }

    /// Closes stdin after what was written before (one serial queue): a `claude -p` that reads
    /// its request as text starts once its input ends.
    func closeInput() {
        writer.async { [self] in
            closeInputNow()
        }
    }

    /// On `writer` only.
    private func closeInputNow() {
        guard !inputClosed else { return }
        inputClosed = true
        try? input.fileHandleForWriting.close()
    }

    /// Closes stdin (Claude Code ends with its input) and stops the process if it still runs.
    /// `atQuit`: waits for the end (half a second at most, then SIGKILL) instead of leaving the
    /// SIGKILL fallback to a background queue the quitting app would not run.
    func stop(atQuit: Bool) {
        writer.async { [self] in
            closeInputNow()
        }
        RunningProcess(process).terminate(waitingUpTo: atQuit ? 0.5 : nil)
    }

    /// The last line the process wrote on stderr, if any: in French when it is a known error,
    /// cut to 200 characters (`ClaudeCLI.lastErrorLine`).
    var lastErrorLine: String? {
        lock.lock()
        defer { lock.unlock() }
        return ClaudeCLI.lastErrorLine(errorTail)
    }

    private func keepError(_ data: Data) {
        lock.lock()
        errorTail = ClaudeCLI.appendingTail(errorTail, data)
        lock.unlock()
    }
}

// MARK: - Short commands

/// Runs a short command (`claude auth status`, the login shell lookup) off the main thread,
/// stopped after `timeout`.
enum ShortRun {
    static func run(_ executable: String, _ arguments: [String], environment: [String: String]?,
                    directory: URL?, timeout: TimeInterval) async -> ShortRunOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<ShortRunOutcome, Never>) in
            let once = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let environment { process.environment = environment }
                if let directory { process.currentDirectoryURL = directory }
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    once.resume(.launchFailed)
                    return
                }
                // At the limit the caller gets its answer even if a child of the command keeps
                // the pipe open: the read below may then stay blocked, never the caller.
                let running = RunningProcess(process)
                let limit = DispatchWorkItem {
                    running.terminate()
                    once.resume(.timedOut)
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: limit)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                limit.cancel()
                once.resume(.finished(status: process.terminationStatus, output: data))
            }
        }
    }
}

/// A process another queue may stop.
final class RunningProcess: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }

    /// SIGTERM now, then SIGKILL if it still runs: a child that ignores or blocks SIGTERM (it
    /// inherits its parent thread's signal mask) never stays behind. The SIGKILL comes after
    /// `grace` on a background queue, or, with `wait`, after waiting that long here.
    func terminate(grace: TimeInterval = 2, waitingUpTo wait: TimeInterval? = nil) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        if let wait {
            let deadline = Date().addingTimeInterval(wait)
            while process.isRunning && Date() < deadline { usleep(10_000) }
            if process.isRunning { kill(pid, SIGKILL) }
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) { [self] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}

/// Resumes a continuation once, whichever of the command's end or its time limit comes first.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
