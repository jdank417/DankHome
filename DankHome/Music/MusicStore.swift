//
//  MusicStore.swift
//  DankHome
//

import MusicKit
import SwiftUI

/// Drives the system Music player (so playback keeps going if the app is closed,
/// and follows whatever AirPlay speaker is selected) and loads library playlists.
@Observable
final class MusicStore {
    private(set) var authorization = MusicAuthorization.currentStatus
    private(set) var playlists: MusicItemCollection<Playlist> = []
    private(set) var errorMessage: String?

    @ObservationIgnored let player = SystemMusicPlayer.shared
    /// Set when playback is controlled while a scene button is being recorded.
    @ObservationIgnored var touched = false

    var isAuthorized: Bool { authorization == .authorized }

    func requestAccess() async {
        authorization = await MusicAuthorization.request()
        if isAuthorized { await loadPlaylists() }
    }

    func loadPlaylists() async {
        guard isAuthorized else { return }
        do {
            var request = MusicLibraryRequest<Playlist>()
            request.sort(by: \.lastPlayedDate, ascending: false)
            request.limit = 20
            playlists = try await request.response().items
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your playlists."
        }
    }

    func play(_ playlist: Playlist) {
        touched = true
        Task {
            player.queue = [playlist]
            await attempt { try await player.play() }
        }
    }

    func togglePlayPause() {
        touched = true
        Task {
            if player.state.playbackStatus == .playing {
                player.pause()
            } else {
                await attempt { try await player.play() }
            }
        }
    }

    func next() {
        touched = true
        Task { await attempt { try await player.skipToNextEntry() } }
    }

    func previous() {
        touched = true
        Task {
            if player.playbackTime > 3 {
                player.restartCurrentEntry()
            } else {
                await attempt { try await player.skipToPreviousEntry() }
            }
        }
    }

    func toggleShuffle() {
        player.state.shuffleMode = player.state.shuffleMode == .songs ? .off : .songs
    }

    func cycleRepeat() {
        player.state.repeatMode = switch player.state.repeatMode {
        case .all: .one
        case .one: MusicPlayer.RepeatMode.none
        default: .all
        }
    }

    private func attempt(_ action: () async throws -> Void) async {
        do {
            try await action()
            errorMessage = nil
        } catch {
            errorMessage = "Playback failed — is Apple Music signed in on this device?"
        }
    }
}
