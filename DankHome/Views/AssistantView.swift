//
//  AssistantView.swift
//  DankHome
//

import SwiftUI

/// Chat with the on-device assistant. Opens listening, so on a wall panel you can
/// tap the sparkle button and just talk.
struct AssistantView: View {
    @Environment(AssistantStore.self) private var assistant
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var voice = VoiceInput()
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: Metrics.gap) {
            header

            if let reason = assistant.unavailableReason {
                ContentUnavailableView("Assistant Unavailable", systemImage: "sparkles",
                                       description: Text(reason))
                    .frame(maxHeight: .infinity)
            } else {
                conversation
                inputBar
            }
        }
        .padding(Metrics.margin)
        .foregroundStyle(.white)
        .background(Color(white: 0.08))
        .preferredColorScheme(.dark)
        .task {
            assistant.prewarm()
            voice.onFinish = { text in
                Task { await send(text, spoken: true) }
            }
            if assistant.unavailableReason == nil, VoiceInput.isSupported { await voice.start() }
        }
        .onDisappear { voice.cancel() }
    }

    private var header: some View {
        HStack(spacing: Metrics.inner) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(LinearGradient(colors: [.cyan, .purple, .pink], startPoint: .leading, endPoint: .trailing))
            Text("Assistant").font(.title3.bold())
            Spacer()
            if !assistant.messages.isEmpty {
                Button("Clear") { assistant.reset() }
                    .buttonStyle(.glass)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.glass)
        }
        .frame(height: Metrics.headerHeight)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.inner) {
                    if assistant.messages.isEmpty {
                        suggestions
                    }
                    ForEach(assistant.messages.filter { !$0.text.isEmpty }) { message in
                        bubble(message)
                            .id(message.id)
                    }
                    if assistant.isResponding, assistant.messages.last?.text.isEmpty != false {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Thinking…").foregroundStyle(.white.opacity(0.6))
                        }
                        .id("thinking")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .onChange(of: assistant.messages) {
                withAnimation { proxy.scrollTo(assistant.messages.last?.id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: Metrics.inner) {
            Text("Ask me to control your home")
                .font(.headline)
            Text("Lights, thermostat, scenes, music and the weather — all handled on this device.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            ForEach(AssistantStore.suggestions(scenes: settings.sceneButtons(home: home).map(\.name)), id: \.self) { suggestion in
                Button {
                    voice.cancel()
                    Task { await send(suggestion, spoken: false) }
                } label: {
                    Text(suggestion)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .frame(height: Metrics.headerHeight)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
    }

    private func bubble(_ message: AssistantStore.Message) -> some View {
        HStack {
            if message.fromUser { Spacer(minLength: 60) }
            Text(message.text)
                .font(.body)
                .foregroundStyle(message.fromUser ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.fromUser ? Color.white : Color.white.opacity(0.12),
                            in: .rect(cornerRadius: 18))
            if !message.fromUser { Spacer(minLength: 60) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if voice.isListening || voice.errorMessage != nil {
                Text(voice.errorMessage ?? (voice.transcript.isEmpty ? "Listening…" : voice.transcript))
                    .font(.subheadline)
                    .foregroundStyle(voice.errorMessage == nil ? .white.opacity(0.8) : .orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
            HStack(spacing: Metrics.inner) {
                Button {
                    typing = false
                    Task { await voice.toggle() }
                } label: {
                    Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                        .font(.title3.weight(.semibold))
                        .symbolEffect(.variableColor.iterative, isActive: voice.isListening)
                        .foregroundStyle(voice.isListening ? .black : .white)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .glassEffect(voice.isListening ? .regular.tint(.white).interactive() : .regular.interactive(), in: .circle)

                TextField("Ask anything…", text: $draft)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(sendDraft)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .glassEffect(.regular, in: .capsule)
                    .onChange(of: typing) { _, isTyping in
                        if isTyping { voice.cancel() }
                    }

                Button(action: sendDraft) {
                    Image(systemName: "arrow.up")
                        .font(.title3.weight(.bold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || assistant.isResponding)
            }
        }
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        typing = true  // keep the keyboard up for a follow-up
        Task { await send(text, spoken: false) }
    }

    private func send(_ text: String, spoken: Bool) async {
        await assistant.send(text, spoken: spoken)
    }
}
