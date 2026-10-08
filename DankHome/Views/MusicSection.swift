//
//  MusicSection.swift
//  DankHome
//

import MusicKit
import SwiftUI

struct NowPlayingPanel: View {
    @Environment(MusicStore.self) private var music
    @ObservedObject private var state = SystemMusicPlayer.shared.state
    @ObservedObject private var queue = SystemMusicPlayer.shared.queue
    var compact = false

    private var entry: MusicPlayer.Queue.Entry? { queue.currentEntry }
    private var isPlaying: Bool { state.playbackStatus == .playing }

    var body: some View {
        Group {
            if music.isAuthorized {
                player
            } else {
                connectPrompt
            }
        }
        .frame(maxWidth: .infinity)
        .card(cornerRadius: 40)
    }

    // MARK: Player

    private var player: some View {
        VStack(spacing: compact ? 16 : 24) {
            HStack {
                SectionTitle(title: "Now Playing", symbol: "music.note")
                Spacer()
                AirPlayButton()
                    .frame(width: 44, height: 44)
            }

            if compact {
                HStack(spacing: 20) {
                    artwork(size: 120)
                    VStack(alignment: .leading, spacing: 12) {
                        titles
                        transport
                    }
                }
            } else {
                artwork(size: 300)
                titles
                progress
                transport
                volume
            }

            if let error = music.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        Group {
            if let artwork = entry?.artwork {
                ArtworkImage(artwork, width: size, height: size)
            } else {
                ZStack {
                    LinearGradient(colors: [.pink, .purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35, weight: .light))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.09))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        .scaleEffect(isPlaying || compact ? 1 : 0.9)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isPlaying)
    }

    private var titles: some View {
        VStack(alignment: compact ? .leading : .center, spacing: 4) {
            Text(entry?.title ?? "Not Playing")
                .font(compact ? .title3.bold() : .title2.bold())
            Text(entry?.subtitle ?? "Pick a playlist below")
                .font(compact ? .body : .title3)
                .foregroundStyle(.white.opacity(0.65))
        }
        .lineLimit(1)
        .multilineTextAlignment(compact ? .leading : .center)
        .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
    }

    private var duration: TimeInterval? {
        guard case let .song(song) = entry?.item else { return nil }
        return song.duration
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let elapsed = SystemMusicPlayer.shared.playbackTime
            let total = duration ?? 0
            VStack(spacing: 6) {
                ProgressView(value: total > 0 ? min(elapsed / total, 1) : 0)
                    .tint(.white)
                HStack {
                    Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                    Spacer()
                    Text("-" + Duration.seconds(max(total - elapsed, 0)).formatted(.time(pattern: .minuteSecond)))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var transport: some View {
        HStack(spacing: compact ? 24 : 0) {
            if !compact {
                iconButton("shuffle", size: 22, active: state.shuffleMode == .songs, action: music.toggleShuffle)
                Spacer()
            }
            iconButton("backward.fill", size: compact ? 26 : 34, action: music.previous)
            if !compact { Spacer() }
            Button(action: music.togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 30 : 40))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: compact ? 64 : 88, height: compact ? 64 : 88)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            if !compact { Spacer() }
            iconButton("forward.fill", size: compact ? 26 : 34, action: music.next)
            if !compact {
                Spacer()
                iconButton(state.repeatMode == .one ? "repeat.1" : "repeat", size: 22,
                           active: state.repeatMode == .all || state.repeatMode == .one, action: music.cycleRepeat)
            }
        }
    }

    private func iconButton(_ symbol: String, size: CGFloat, active: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? .white : .white.opacity(0.4))
                .frame(width: 56, height: 56)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var volume: some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.fill").foregroundStyle(.white.opacity(0.6))
            SystemVolumeSlider().frame(height: 34)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: Not connected

    private var connectPrompt: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 64))
                .foregroundStyle(.pink.gradient)
            Text("Connect Apple Music")
                .font(.title2.bold())
            Text(music.authorization == .denied
                 ? "Music access is off. Turn it on in Settings › DankHome."
                 : "Play your playlists on any speaker in the house.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
            if music.authorization == .notDetermined {
                Button("Connect") { Task { await music.requestAccess() } }
                    .buttonStyle(.glassProminent)
                    .tint(.pink)
                    .controlSize(.large)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 40)
    }
}

struct PlaylistShelf: View {
    @Environment(MusicStore.self) private var music

    var body: some View {
        if music.isAuthorized, !music.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Playlists", symbol: "music.note.list")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(music.playlists) { playlist in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                music.play(playlist)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Group {
                                        if let artwork = playlist.artwork {
                                            ArtworkImage(artwork, width: 140, height: 140)
                                        } else {
                                            Rectangle().fill(.white.opacity(0.1))
                                                .overlay(Image(systemName: "music.note.list").font(.largeTitle))
                                        }
                                    }
                                    .frame(width: 140, height: 140)
                                    .clipShape(.rect(cornerRadius: 18))
                                    Text(playlist.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                        .frame(width: 140, alignment: .leading)
                                }
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}
