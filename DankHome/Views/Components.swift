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
        // The glows live in an overlay so their size never stretches the screen layout.
        base
            .overlay {
                ZStack {
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
            }
            .clipped()
            .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: a)
        .animation(.easeInOut(duration: 1.2), value: b)
    }
}

/// One spacing system for the whole dashboard. Every gap, padding and corner uses these.
enum Metrics {
    /// Distance from the screen edge to the content.
    static let margin: CGFloat = 20
    /// Gap between cards, tiles, sections and rows of controls.
    static let gap: CGFloat = 12
    /// Padding inside every card.
    static let cardPadding: CGFloat = 16
    /// Space between rows inside a card.
    static let inner: CGFloat = 10
    /// Gap between small chips and buttons in a row.
    static let chipGap: CGFloat = 8
    /// Corner radius for cards and tiles.
    static let radius: CGFloat = 20
    /// Height of headers, chips and buttons, so rows line up.
    static let headerHeight: CGFloat = 38
}

/// Header above a dashboard section: title on the left, optional controls on the right.
struct SectionHeader<Trailing: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Metrics.chipGap) {
            SectionTitle(title: title, symbol: symbol)
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: Metrics.headerHeight)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, symbol: String) {
        self.init(title: title, symbol: symbol) { EmptyView() }
    }
}

struct SectionTitle: View {
    var title: String
    var symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.white.opacity(0.7))
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

extension View {
    func card(cornerRadius: CGFloat = Metrics.radius, padding: CGFloat = Metrics.cardPadding) -> some View {
        self.padding(padding)
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

/// System volume slider with a small thumb — follows the active AirPlay speaker.
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.tintColor = .white
        view.setVolumeThumbImage(Self.thumb, for: .normal)
        view.setVolumeThumbImage(Self.thumb, for: .highlighted)
        return view
    }

    private static let thumb: UIImage = {
        let size = CGSize(width: 14, height: 14)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
    }()

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
