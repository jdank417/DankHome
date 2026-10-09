//
//  MusicSection.swift
//  DankHome
//

import MusicKit
import SwiftUI

/// Small "now playing" card: artwork, song, and play controls. One row when there's
/// width for it (portrait), two rows in the narrow side panel.
struct NowPlayingCard: View {
    @Environment(MusicStore.self) private var music
    @ObservedObject private var state = SystemMusicPlayer.shared.state
    @ObservedObject private var queue = SystemMusicPlayer.shared.queue
    var twoRows = false

    private var entry: MusicPlayer.Queue.Entry? { queue.currentEntry }
    private var isPlaying: Bool { state.playbackStatus == .playing }

    @Environment(AppSettings.self) private var settings

    private var artSize: CGFloat { twoRows ? 64 : 60 }
    /// Blurred artwork fills the card behind the controls, like Apple Music.
    private var showsBackdrop: Bool { settings.prefs.tintMusicCard && entry?.artwork != nil }

    var body: some View {
        Group {
            if music.isAuthorized {
                if twoRows {
                    VStack(spacing: Metrics.inner) {
                        HStack(spacing: Metrics.inner) {
                            artwork
                            titles
                            AirPlayButton().frame(width: 32, height: 32)
                        }
                        transport
                        volume
                    }
                } else {
                    HStack(spacing: Metrics.inner) {
                        artwork
                        titles
                        transport
                        volume
                            .frame(maxWidth: 200)
                        AirPlayButton().frame(width: 32, height: 32)
                    }
                }
            } else {
                connectPrompt
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(Metrics.cardPadding)
        .background {
            if showsBackdrop, let artwork = entry?.artwork {
                backdrop(artwork)
                    .transition(.opacity)
            }
        }
        .clipShape(.rect(cornerRadius: Metrics.radius))
        .glassEffect(showsBackdrop ? .clear : .regular, in: .rect(cornerRadius: Metrics.radius))
        .animation(.easeInOut(duration: 0.8), value: entry?.id)
        // Swipe the card sideways to skip songs.
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard music.isAuthorized, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            if value.translation.width < -60 { Feedback.tap(); music.next() }
            else if value.translation.width > 60 { Feedback.tap(); music.previous() }
        })
    }

    /// The cover, scaled up, heavily blurred and darkened so white text stays readable.
    private func backdrop(_ artwork: Artwork) -> some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height) * 1.3
            ArtworkImage(artwork, width: 300, height: 300)
                .scaledToFill()
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .blur(radius: 40, opaque: true)
                .saturation(1.3)
                .overlay(LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.55)],
                                        startPoint: .top, endPoint: .bottom))
        }
        .clipped()
    }

    private var artwork: some View {
        Group {
            if let artwork = entry?.artwork {
                // Request at 2× so it stays sharp on Retina.
                ArtworkImage(artwork, width: artSize * 2, height: artSize * 2)
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note")
                        .font(.system(size: artSize * 0.38, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .frame(width: artSize, height: artSize)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .contentShape(.rect)
        .onTapGesture {
            guard entry != nil else { return }
            Feedback.tap()
            // Apple Music is what the system player plays through.
            if let url = URL(string: "music://") { UIApplication.shared.open(url) }
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry?.title ?? "Not Playing")
                .font(.subheadline.weight(.semibold))
            Text(music.errorMessage ?? entry?.subtitle ?? "Apple Music")
                .font(.caption)
                .foregroundStyle(music.errorMessage == nil ? .white.opacity(0.65) : .orange)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transport: some View {
        HStack(spacing: 4) {
            iconButton("backward.fill", action: music.previous)
            Button(action: music.togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Metrics.headerHeight + 6, height: Metrics.headerHeight + 6)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            iconButton("forward.fill", action: music.next)
        }
    }

    private var volume: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            SystemVolumeSlider()
                .frame(height: 20)
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: Metrics.headerHeight, height: Metrics.headerHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var connectPrompt: some View {
        HStack(spacing: Metrics.inner) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 24))
                .foregroundStyle(.pink.gradient)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Music").font(.subheadline.weight(.semibold))
                Text(music.authorization == .denied ? "Turn on in Settings › DankHome" : "Not connected")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if music.authorization == .notDetermined {
                Button("Connect") { Task { await music.requestAccess() } }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.glassProminent)
                    .tint(.pink)
            }
        }
    }
}
