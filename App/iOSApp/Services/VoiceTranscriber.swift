import Foundation
import Speech
import AVFoundation

/// On-device speech → text for filling in a vial by voice. Uses Apple's `SFSpeechRecognizer` with
/// `requiresOnDeviceRecognition = true`, so audio is transcribed on the phone and never uploaded —
/// the same privacy posture as the photo scanner and the assistant. The resulting transcript is fed
/// to the SAME `LabelAI.extract` pipeline the photo scanner uses, so voice is just a second input
/// source: the extractor (on-device Apple Intelligence on iOS 26, regex otherwise) doesn't care
/// whether the text came from OCR or speech.
///
/// This is the engine only — no UI. A caller drives it: `authorize()` → `start()` → `stop()`, then
/// reads `transcript` (or calls `scannedLabel(extraNames:)`). The caller is responsible for calling
/// `stop()` when it's done (e.g. on view disappear), since a MainActor object can't tear the audio
/// engine down from `deinit`.
@Observable
@MainActor
final class VoiceTranscriber {
    enum Status: Equatable {
        case idle          // never started, or reset
        case listening     // actively capturing + transcribing
        case finished      // stopped; `transcript` holds the result
        case denied        // mic or speech permission refused
        case unavailable   // on-device recognition not available / failed to start
    }

    /// The recognized text — updated live with partial results while listening.
    private(set) var transcript: String = ""
    private(set) var status: Status = .idle
    private(set) var errorText: String?

    var isListening: Bool { status == .listening }

    // en-US: labels are English, and on-device support is most reliable here. Swap the locale if the
    // app later localizes vial entry.
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Whether on-device transcription can run at all on this device/locale. Check before offering
    /// voice entry in the UI.
    var isSupported: Bool {
        guard let recognizer else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    /// Ask for speech + microphone permission. Returns true only if BOTH are granted. Sets
    /// `status = .denied` otherwise.
    func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speech == .authorized else { status = .denied; return false }

        let mic = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        if !mic { status = .denied }
        return mic
    }

    /// Begin on-device transcription. Call `authorize()` first. Safe to call again — it resets any
    /// prior run. Partial results stream into `transcript`; call `stop()` when the user is done.
    func start() {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            status = .unavailable
            return
        }
        teardown()                 // clear any prior session
        transcript = ""
        errorText = nil

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true      // never leaves the phone
        request = req

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorText = "Couldn't start the microphone."
            status = .unavailable
            return
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Capture `req` directly (not self) so the audio-thread tap needs no actor hop.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorText = "Couldn't start recording."
            status = .unavailable
            teardown()
            return
        }
        status = .listening

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            // The completion handler fires off the main actor; pull out only Sendable primitives,
            // then hop back to the MainActor to mutate observable state.
            let text = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text { self.transcript = text }
                if done { self.finishListening() }
            }
        }
    }

    /// Stop listening. The accumulated text stays in `transcript`.
    func stop() {
        finishListening()
    }

    /// Clear the transcript and return to idle (e.g. to start a fresh capture).
    func reset() {
        teardown()
        transcript = ""
        errorText = nil
        status = .idle
    }

    /// Convenience: run the current transcript through the SAME extractor the photo scanner uses.
    /// Returns a `ScannedLabel` a caller can hand to the add-vial form exactly like a scan result.
    func scannedLabel(extraNames: [String]) async -> ScannedLabel {
        await LabelAI.extract(from: transcript, extraNames: extraNames)
    }

    private func finishListening() {
        let wasListening = (status == .listening)
        teardown()
        if wasListening { status = .finished }
    }

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
