//
//  VoiceInput.swift
//  DankHome
//

import AVFoundation
import Speech

/// Push-to-talk speech recognition, done on the device. Stops on its own after a
/// short pause and hands back what was said.
@Observable
final class VoiceInput {
    private(set) var transcript = ""
    private(set) var isListening = false
    private(set) var errorMessage: String?

    /// Called with the final text when the person stops talking.
    @ObservationIgnored var onFinish: ((String) -> Void)?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer()
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Task<Void, Never>?

    func toggle() async {
        if isListening { finish() } else { await start() }
    }

    /// The Simulator can't reach the Mac's microphone reliably, so voice is device-only.
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    func start() async {
        guard !isListening else { return }
        errorMessage = nil
        guard Self.isSupported else {
            errorMessage = "Voice works on a real device, not the Simulator."
            return
        }
        guard await Self.requestPermissions() else {
            errorMessage = "Allow the microphone and speech recognition in Settings › DankHome."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        do {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

            // Audio hardware setup can block, so it never runs on the main thread.
            let engine = try await Self.startEngine(feeding: request)

            self.engine = engine
            self.request = request
            transcript = ""
            isListening = true
            task = Self.recognize(with: recognizer, request: request) { [weak self] text, isFinal in
                let voice = self
                Task { @MainActor in voice?.received(text, isFinal: isFinal) }
            }
            restartSilenceTimer(seconds: 6)
        } catch {
            errorMessage = "Couldn't start the microphone."
            cleanUp()
        }
    }

    /// Stops listening and delivers the transcript.
    func finish() {
        guard isListening else { return }
        let text = transcript
        cleanUp()
        if !text.isEmpty { onFinish?(text) }
    }

    func cancel() {
        cleanUp()
        transcript = ""
        errorMessage = nil
    }

    private func received(_ text: String?, isFinal: Bool) {
        guard isListening else { return }
        if let text { transcript = text }
        if isFinal { finish() } else { restartSilenceTimer(seconds: 0.8) }
    }

    private func restartSilenceTimer(seconds: Double) {
        silenceTimer?.cancel()
        silenceTimer = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func cleanUp() {
        silenceTimer?.cancel()
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // These run off the main thread (audio and recognition callbacks), so they're nonisolated.

    @concurrent
    nonisolated private static func startEngine(feeding request: SFSpeechAudioBufferRecognitionRequest) async throws -> AVAudioEngine {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let node = engine.inputNode
        node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
        return engine
    }

    nonisolated private static func recognize(with recognizer: SFSpeechRecognizer,
                                              request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, result?.isFinal == true || error != nil)
        }
    }

    nonisolated private static func requestPermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speechAllowed else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
