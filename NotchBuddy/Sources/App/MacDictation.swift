import AVFoundation
import Speech

/// Speech to text for the notch chat, on-device when the Mac supports it.
/// Not main-actor bound, because the audio tap and the
/// recognizer call back on their own threads; the published values are set on the main actor.
@Observable
final class MacDictation: @unchecked Sendable {
    var isRecording = false
    var transcript = ""
    /// What was typed before dictating, kept in front of the words.
    var prefix = ""

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    /// A start under way, from the click to the end of `start()`, the permission prompts included:
    /// another click meanwhile does nothing. Two starts would install two taps on the input bus,
    /// and AVAudioEngine raises an exception on the second (the app would end).
    @ObservationIgnored private var starting = false

    /// What the chat shows when the Mac has no microphone input (a closed lid with a display that
    /// has none): dictation does not start.
    static let noInputMessage = String(localized: "Aucun micro disponible : la dictée ne peut pas démarrer.")

    /// The text field's content: what was typed, then the words heard so far.
    var text: String { prefix + transcript }

    /// Starts dictation, or stops it when it runs. Returns a line for the chat when it could not
    /// start for want of a microphone, nil otherwise (a refused permission says nothing, as before).
    @MainActor @discardableResult
    func toggle(startingFrom text: String) async -> String? {
        if isRecording { stop(); return nil }
        guard !starting else { return nil }
        starting = true
        defer { starting = false }
        guard await Self.authorized() else { return nil }
        // Checked again after the prompts: nothing may have started in the meantime.
        guard !isRecording, request == nil else { return nil }
        prefix = text.isEmpty || text.hasSuffix(" ") ? text : text + " "
        transcript = ""
        return start()
    }

    /// Nonisolated, so the tap and recognizer closures formed here run on their own threads; called
    /// on the main actor only (`toggle`).
    nonisolated private func start() -> String? {
        // The app's language first (Settings → General → Language), then the system's.
        let localeID = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en-US"
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { return nil }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // No input device: a format with no channel (or no rate), on which installTap raises.
        guard format.channelCount > 0, format.sampleRate > 0 else { return Self.noInputMessage }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        // Recording from before the tap: a click from here on stops it, never starts it again.
        isRecording = true
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            isRecording = false
            return nil
        }
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self else { return }
                if let words { self.transcript = words }
                if done { self.stop() }
            }
        }
        return nil
    }

    @MainActor func stop() {
        guard isRecording || request != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
    }

    private static func authorized() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
