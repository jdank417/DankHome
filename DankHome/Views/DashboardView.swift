//
//  DashboardView.swift
//  DankHome
//

import MusicKit
import SwiftUI

struct DashboardView: View {
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @Environment(AppSettings.self) private var settings
    @Environment(IdleMonitor.self) private var idle
    @ObservedObject private var queue = SystemMusicPlayer.shared.queue
    @State private var showSettings = false

    private var artworkColor: Color {
        queue.currentEntry?.artwork?.backgroundColor.map(Color.init(cgColor:)) ?? .indigo
    }

    private var lightGlow: Color {
        home.visibleLights.first(where: \.isOn)?.tint ?? Color(white: 0.15)
    }

    var body: some View {
        let prefs = settings.prefs
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height && proxy.size.width > 900
            ZStack {
                AmbientBackground(theme: prefs.theme, accent: artworkColor, glow: lightGlow)

                if landscape {
                    HStack(alignment: .top, spacing: 28) {
                        if prefs.musicOnLeft { musicColumn(width: proxy.size.width) }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 28) {
                                header
                                LightsGrid()
                                if prefs.showScenes { ScenesRow() }
                                if prefs.showClimate || prefs.showWeather { ClimateSection(sideBySide: true) }
                            }
                            .padding(.vertical, 8)
                        }
                        .scrollIndicators(.hidden)
                        if !prefs.musicOnLeft { musicColumn(width: proxy.size.width) }
                    }
                    .padding(32)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            header
                            NowPlayingPanel(compact: proxy.size.width < 700)
                            LightsGrid()
                            if prefs.showScenes { ScenesRow() }
                            if prefs.showClimate || prefs.showWeather { ClimateSection(sideBySide: proxy.size.width >= 700) }
                            if prefs.showPlaylists { PlaylistShelf() }
                        }
                        .padding(proxy.size.width < 700 ? 20 : 32)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .task { await music.loadPlaylists() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationSizing(.page)
        }
        .onChange(of: idle.isSleeping) { _, sleeping in
            if sleeping { showSettings = false }
        }
    }

    private func musicColumn(width: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                NowPlayingPanel()
                if settings.prefs.showPlaylists { PlaylistShelf() }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .frame(width: min(440, width * 0.38))
    }

    private var header: some View {
        let prefs = settings.prefs
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prefs.formatTime(context.date))
                            .font(prefs.clock.font(size: 96))
                            .monospacedDigit()
                            .foregroundStyle(prefs.clock.color.color)
                        if prefs.showDate {
                            Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                                .font(.title2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    HStack(spacing: 12) {
                        Text(home.selectedRoom ?? home.homeName)
                            .font(.title3.bold())
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                    }
                    if prefs.showWeather { WeatherSummary() }
                    if home.isDemo {
                        Label("Demo — no HomeKit home found", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .foregroundStyle(.white)

            if let problem = home.authorizationProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            RoomPicker()
        }
    }
}

#Preview(traits: .landscapeLeft) {
    DashboardView()
        .environment(HomeStore())
        .environment(MusicStore())
        .environment(AppSettings())
        .environment(WeatherStore())
        .environment(IdleMonitor())
}
