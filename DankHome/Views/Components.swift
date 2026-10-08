//
//  Components.swift
//  DankHome
//

import AVKit
import MediaPlayer
import SwiftUI

/// Dark backdrop with two soft glows. The Ambient theme picks up the album artwork
/// color and the lights' color; other themes use fixed colors.
struct AmbientBackground: View {
    var theme: BackgroundTheme
    var accent: Color
    var glow: Color

    var body: some View {
        let (base, themeA, themeB) = theme.colors
        let a = theme == .ambient ? accent : themeA
        let b = theme == .ambient ? glow : themeB
        ZStack {
            base
            Circle()
                .fill(a.opacity(0.55))
                .frame(width: 900, height: 900)
                .blur(radius: 220)
                .offset(x: 420, y: -260)
            Circle()
                .fill(b.opacity(0.35))
                .frame(width: 800, height: 800)
                .blur(radius: 220)
                .offset(x: -380, y: 320)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: a)
        .animation(.easeInOut(duration: 1.2), value: b)
    }
}

struct SectionTitle: View {
    var title: String
    var symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(.white.opacity(0.7))
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

extension View {
    func card(cornerRadius: CGFloat = 32) -> some View {
        padding(24)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

/// System AirPlay picker — choose HomePods / AirPlay speakers for the music.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .systemCyan
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// System volume slider — follows the active AirPlay speaker.
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
