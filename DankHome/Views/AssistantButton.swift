//
//  AssistantButton.swift
//  DankHome
//

import SwiftUI

/// The ✨ button. Tap to open the assistant; press and hold to talk, let go to send —
/// the answer pops up on the dashboard without opening anything.
struct AssistantButton: View {
    @Environment(AssistantStore.self) private var assistant
    @Environment(UndoCenter.self) private var undo
    @Environment(HomeStore.self) private var home
    var talk: PushToTalk
    var onTap: () -> Void

    @State private var didHold = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: talk.voice.isListening ? "waveform" : "sparkles")
            .font(.body.weight(.semibold))
            .symbolEffect(.variableColor.iterative, isActive: talk.voice.isListening)
            .foregroundStyle(talk.voice.isListening ? .black : .white)
            .frame(width: Metrics.headerHeight, height: Metrics.headerHeight)
            .glassEffect(talk.voice.isListening ? .regular.tint(.white) : .regular, in: .circle)
            .scaleEffect(talk.voice.isListening ? 1.15 : holdTask != nil ? 0.92 : 1)
            .animation(.spring(response: 0.3), value: talk.voice.isListening)
            .animation(.spring(response: 0.2), value: holdTask != nil)
            .contentShape(.circle)
            // One gesture tells a tap (open the assistant) from a hold (talk).
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard holdTask == nil else { return }
                        didHold = false
                        holdTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            didHold = true
                            Feedback.press()
                            talk.start(assistant: assistant, undo: undo, home: home)
                        }
                    }
                    .onEnded { _ in
                        holdTask?.cancel()
                        holdTask = nil
                        if didHold {
                            talk.voice.finish()
                        } else {
                            Feedback.tap()
                            onTap()
                        }
                        didHold = false
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Assistant")
            .accessibilityHint("Tap to open, or hold to talk.")
            .accessibilityAction { onTap() }
    }
}

/// State for hold-to-talk: what's being heard, then the reply.
@Observable
final class PushToTalk {
    let voice = VoiceInput()
    private(set) var reply: String?
    private(set) var isThinking = false
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    var isVisible: Bool { voice.isListening || isThinking || reply != nil || voice.errorMessage != nil }

    func start(assistant: AssistantStore, undo: UndoCenter, home: HomeStore) {
        hideTask?.cancel()
        reply = nil
        voice.onFinish = { [weak self] text in
            guard let self else { return }
            Task {
                self.isThinking = true
                await undo.perform("Assistant: \(text)", home: home) {
                    await assistant.send(text, spoken: true)
                }
                self.isThinking = false
                self.show(assistant.messages.last(where: { !$0.fromUser })?.text ?? "Done.")
            }
        }
        Task {
            await voice.start()
            if voice.errorMessage != nil { scheduleHide(after: 4) }
        }
    }

    func dismiss() {
        hideTask?.cancel()
        voice.cancel()
        withAnimation(.snappy) { reply = nil }
    }

    private func show(_ text: String) {
        withAnimation(.snappy) { reply = text }
        scheduleHide(after: 7)
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                reply = nil
                voice.cancel()
            }
        }
    }
}

/// Floating bubble under the header while talking and for the reply.
struct PushToTalkBubble: View {
    var talk: PushToTalk

    var body: some View {
        if talk.isVisible {
            HStack(spacing: Metrics.inner) {
                Image(systemName: talk.voice.isListening ? "mic.fill" : "sparkles")
                    .font(.title3)
                    .foregroundStyle(LinearGradient(colors: [.cyan, .purple, .pink], startPoint: .leading, endPoint: .trailing))
                    .symbolEffect(.pulse, isActive: talk.voice.isListening || talk.isThinking)
                Text(text)
                    .font(.body.weight(.medium))
                    .foregroundStyle(talk.voice.errorMessage != nil ? .orange : .white)
                    .lineLimit(3)
                    .contentTransition(.opacity)
                if talk.reply != nil {
                    Button {
                        talk.dismiss()
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: 560)
            .glassEffect(.regular, in: .rect(cornerRadius: Metrics.radius))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var text: String {
        if let error = talk.voice.errorMessage { return error }
        if talk.voice.isListening { return talk.voice.transcript.isEmpty ? "Listening… let go when you're done." : talk.voice.transcript }
        if talk.isThinking { return talk.voice.transcript.isEmpty ? "Thinking…" : "“\(talk.voice.transcript)”" }
        return talk.reply ?? ""
    }
}
