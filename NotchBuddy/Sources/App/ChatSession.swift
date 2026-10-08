import Foundation
import Combine

// MARK: - The quick chat, through the user's own Claude Code (Task 14)
//
// One long-lived `claude -p` process per conversation (`ClaudeCLI.chatArguments`: Haiku, no
// tool, no hook, nothing saved), started on the first message. Each message is one
// `stream-json` line on its stdin; the answer streams back on stdout, read by a
// `readabilityHandler` into a `ClaudeStreamParser` and written into `AppState.chatHistory` on
// the main actor. The island stores no key and no token: Claude Code uses the user's own
// claude.ai login.
//
// Lifecycle: the process waits on stdin between messages (it costs nothing) and is stopped
// after 10 minutes without a message (one DispatchWorkItem, rescheduled at each message and at
// each answer's end), on « Nouvelle conversation » (`reset`) and when the app quits (`stop`).
// Every stop moves `ChatTurnToken` to a new generation, and every callback of a process carries
// the generation it was started in: the tail of an answer from a stopped process is dropped,
// never written into the next conversation.

@MainActor
final class ChatSession: ObservableObject {
    static let shared = ChatSession()

    typealias Availability = ChatAvailability

    /// What the last check found, nil before the first one. The chat view shows the install or
    /// login message from it.
    @Published private(set) var knownAvailability: Availability?
    /// From a message until the end of its answer. One answer at a time.
    @Published private(set) var isAnswering = false

    /// The answer being written: its generation, its bubble and the state that holds it.
    private struct Turn {
        let generation: Int
        let bubbleID: UUID
        let state: AppState
        var text = ""
    }

    private var token = ChatTurnToken()
    private var process: ChatProcess?
    private var parser = ClaudeStreamParser()
    private var turn: Turn?
    /// The window or file already sent to the live process, so it goes once.
    private var sentContextKey: String?
    /// The live process has had a message: the earlier exchanges go only with the first one.
    private var processHasMessages = false
    /// The live process closed its stdout (everything it wrote has been read).
    private var outputClosed = false
    private var idleStop: DispatchWorkItem?

    /// Where `claude` is: kept while it stays executable.
    private var binaryPath: String?
    /// The login shell lookup, run once for the app's life.
    private var shellLookup: Task<String?, Never>?
    private var availabilityCheck: Task<Availability, Never>?

    private let systemPrompt = ClaudeCLI.chatSystemPrompt(firstName: resolveUserFirstName())

    static let genericError = "Claude Code s'est arrêté pendant la réponse."
    static let emptyAnswer = "Claude n'a rien répondu."
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
    /// login shell (`command -v claude`, 3 s at most, off the main thread).
    private func locateBinary() async -> String? {
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

    nonisolated private static func environment(for binary: String) -> [String: String] {
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
        state.stateOverride = .thinking
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
            let outcome = await Task.detached(priority: .userInitiated) { ChatAttachment.load(url: fileURL) }.value
            guard token.accepts(generation) else { return }
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
        guard let process, token.accepts(generation) else { return }

        let transcript = processHasMessages ? nil : ChatOutgoing.transcript(earlier)
        let outgoing = ChatOutgoing.compose(query: query,
                                            windowContext: contextDue ? windowLine : nil,
                                            attachment: attachment,
                                            transcript: transcript)
        if contextDue { sentContextKey = contextKey }
        processHasMessages = true
        process.write(outgoing.line)
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
        let interrupted = turn
        stopProcess()
        turn = nil
        isAnswering = false
        if let interrupted {
            removeBubbleIfEmpty(interrupted)
            interrupted.state.stateOverride = nil
        }
    }

    /// Stops the process for good (the app quits).
    func stop() {
        reset()
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
        let started = ChatProcess()
        do {
            try started.start(
                binary: binary,
                arguments: ClaudeCLI.chatArguments(systemPrompt: systemPrompt),
                environment: Self.environment(for: binary),
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
        outputClosed = false
        return true
    }

    /// Runs `body` on the main actor, in the order the calls were made (FIFO main queue): the
    /// end of the output is seen after the last piece of it.
    nonisolated private static func onMain(_ body: @escaping @MainActor @Sendable (ChatSession) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { body(ChatSession.shared) }
        }
    }

    /// One read of stdout: the events it completes, written into the answer's bubble once.
    private func received(_ data: Data, generation: Int) {
        guard token.accepts(generation), process != nil else { return }
        let events = parser.feed(data)
        // Output between two answers (none is expected) has no bubble to go to.
        guard var current = turn, current.generation == generation else { return }
        var end: (isError: Bool, message: String?)?
        for event in events where end == nil {
            switch event {
            case .textDelta(let piece):
                current.text += piece
            case .assistantText(let whole):
                current.text = whole
            case .turnEnded(let isError, let message):
                end = (isError, message)
            case .initialized, .toolUse, .toolResult:
                break
            }
        }
        turn = current
        writeBubble(current)
        if let end { finishTurn(isError: end.isError, message: end.message) }
    }

    /// The answer is over: kept in its bubble, or an error note.
    private func finishTurn(isError: Bool, message: String?) {
        guard var current = turn else { return }
        turn = nil
        isAnswering = false
        scheduleIdleStop()
        if isError {
            showError(current, message: Self.nonEmpty(message) ?? process?.lastErrorLine ?? Self.genericError)
            return
        }
        if current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let message {
            current.text = message
            writeBubble(current)
        }
        guard !current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError(current, message: Self.emptyAnswer)
            return
        }
        current.state.stateOverride = nil
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
    }

    /// stdout closed: everything the process wrote has been read.
    private func outputEnded(generation: Int) {
        guard token.accepts(generation), process != nil else { return }
        outputClosed = true
        processEnded(generation: generation)
    }

    /// The process exited. When an answer is in progress, its last lines may still be on
    /// their way through stdout: they get a second before the answer is called failed.
    private func exited(generation: Int) {
        guard token.accepts(generation), process != nil else { return }
        if outputClosed || turn == nil {
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
        showError(interrupted, message: errorLine ?? Self.genericError)
    }

    /// Stops the live process, if any, and moves to a new generation so that nothing it still
    /// sends is read.
    private func stopProcess() {
        token.reset()
        idleStop?.cancel()
        idleStop = nil
        process?.stop()
        process = nil
        parser = ClaudeStreamParser()
        sentContextKey = nil
        processHasMessages = false
        outputClosed = false
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
              history[index].content != current.text else { return }
        current.state.chatHistory[index].content = current.text
    }

    private func removeBubbleIfEmpty(_ current: Turn) {
        current.state.chatHistory.removeAll {
            $0.id == current.bubbleID && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The error note of the chat, as before: Klay in error, the message on the note view.
    private func showError(_ current: Turn, message: String) {
        removeBubbleIfEmpty(current)
        current.state.stateOverride = .error
        current.state.noteMessage = message
        current.state.view = .note
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
        binaryPath = nil
        knownAvailability = .missingCLI
        guard let current = turn else { return }
        turn = nil
        isAnswering = false
        removeBubbleIfEmpty(current)
        current.state.stateOverride = nil
    }

    /// The dropped file cannot go to Claude: a note says why, Claude is not started, and the
    /// file leaves the chat (the next messages go without it).
    private func refuseAttachment(_ message: String, file: URL) {
        if let current = turn, case .file(_, let url)? = current.state.promptContext, url == file {
            current.state.promptContext = nil
        }
        failTurn(message)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

// MARK: - The chat process

/// The long-lived `claude` process of the chat and its three pipes. Its callbacks run on
/// background queues: they only touch what is immutable here, or `errorTail` behind `lock`.
private final class ChatProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    /// Writes go through one serial queue: a line with an image is megabytes, and the pipe
    /// only drains as fast as Claude Code reads it, which must never block the main thread.
    private let writer = DispatchQueue(label: "ai.klayer.island.chat.stdin")
    private let lock = NSLock()
    private var errorTail = Data()

    /// Starts the process. `onOutput` gets each read of stdout, `onOutputEnd` its end, `onExit`
    /// the exit: all on background queues.
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

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                // End of file: the handler would be called again and again, for nothing.
                handle.readabilityHandler = nil
                onOutputEnd()
            } else {
                onOutput(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                self?.keepError(data)
            }
        }
        process.terminationHandler = { ended in onExit(ended.terminationStatus) }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            throw error
        }
    }

    /// Writes one line on stdin. A write that fails (the process is gone) is dropped: the end
    /// of the process is reported by `onExit`.
    func write(_ line: String) {
        let data = Data(line.utf8)
        writer.async { [self] in
            try? input.fileHandleForWriting.write(contentsOf: data)
        }
    }

    /// Closes stdin (Claude Code ends with its input) and stops the process if it still runs.
    func stop() {
        writer.async { [self] in
            try? input.fileHandleForWriting.close()
        }
        if process.isRunning { process.terminate() }
    }

    /// The last line the process wrote on stderr, if any.
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
private final class RunningProcess: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }
    func terminate() {
        if process.isRunning { process.terminate() }
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
