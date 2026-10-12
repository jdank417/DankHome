//
//  DashboardView.swift
//  DankHome
//

import MusicKit
import SwiftUI

/// Everything on one screen. Nothing scrolls: every section is sized from the space
/// available, and rows that run out of room collapse instead of overflowing.
///
/// Landscape: a side panel (thermostat · forecast · now playing) next to the lights.
/// Portrait: now playing on top, lights in the middle, thermostat and forecast below.
struct DashboardView: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    @Environment(IdleMonitor.self) private var idle
    @Environment(SceneRecorder.self) private var recorder
    @Environment(WeatherStore.self) private var weather
    @ObservedObject private var queue = SystemMusicPlayer.shared.queue
    @State private var showSettings = false
    @State private var showAssistant = false
    @State private var showEnergy = false
    @State private var talk = PushToTalk()

    private var artworkColor: Color {
        queue.currentEntry?.artwork?.backgroundColor.map(Color.init(cgColor:)) ?? .indigo
    }

    private var lightGlow: Color {
        home.visibleLights.first(where: \.isOn)?.tint ?? Color(white: 0.15)
    }

    private var thermostat: Thermostat? {
        settings.prefs.showClimate ? home.visibleThermostats.first : nil
    }

    var body: some View {
        let prefs = settings.prefs
        GeometryReader { proxy in
            let size = proxy.size
            let landscape = size.width > size.height
            ZStack {
                AmbientBackground(theme: prefs.theme, accent: artworkColor, glow: lightGlow)
                if prefs.weatherEffects, !idle.isSleeping, let current = weather.current {
                    WeatherEffectsView(effect: WeatherEffect(code: current.code))
                        .ignoresSafeArea()
                }

                VStack(alignment: .leading, spacing: Metrics.gap) {
                    if recorder.isRecording { RecordingBanner() }
                    header(size: size, landscape: landscape)
                    if landscape {
                        landscapeBody(size: size)
                    } else {
                        portraitBody(size: size)
                    }
                }
                .padding(Metrics.margin)
                .frame(width: size.width, height: size.height, alignment: .top)
            }
            .overlay(alignment: .top) {
                PushToTalkBubble(talk: talk)
                    .padding(.top, 96)
                    .padding(.horizontal, Metrics.margin)
            }
            .overlay {
                // Red frame while a scene button is being recorded.
                if recorder.isRecording {
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(.red, lineWidth: 5)
                        .shadow(color: .red.opacity(0.8), radius: 14)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: recorder.isRecording)
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationSizing(.page)
        }
        .sheet(isPresented: $showAssistant) {
            AssistantView()
                .presentationSizing(.form)
        }
        .sheet(isPresented: $showEnergy) {
            EnergyView()
                .presentationSizing(.form)
        }
        .sheet(item: Bindable(recorder).review) { review in
            RecordingReviewView(review: review)
        }
        .onChange(of: recorder.isRecording) { _, recording in
            // Recording happens on the dashboard itself.
            if recording { showSettings = false }
        }
        .onChange(of: idle.isSleeping) { _, sleeping in
            if sleeping {
                showSettings = false
                showAssistant = false
                showEnergy = false
                talk.dismiss()
            }
        }
    }

    // MARK: - Layouts

    private func landscapeBody(size: CGSize) -> some View {
        let prefs = settings.prefs
        let showPanel = thermostat != nil || prefs.showWeather || prefs.showMusic
        let panelWidth = (size.width * 0.26).clamped(to: 280...340)
        return HStack(alignment: .top, spacing: Metrics.gap) {
            if showPanel && prefs.sidePanelOnLeft { sidePanel(size: size).frame(width: panelWidth) }
            lightsSection(width: size.width - Metrics.margin * 2 - (showPanel ? panelWidth + Metrics.gap : 0))
            if showPanel && !prefs.sidePanelOnLeft { sidePanel(size: size).frame(width: panelWidth) }
        }
        .frame(maxHeight: .infinity)
    }

    private func portraitBody(size: CGSize) -> some View {
        let prefs = settings.prefs
        return VStack(alignment: .leading, spacing: Metrics.gap) {
            RoomPicker()
            if prefs.showMusic { NowPlayingCard() }
            lightsSection(width: size.width - Metrics.margin * 2)
            if thermostat != nil || prefs.showWeather {
                HStack(alignment: .top, spacing: Metrics.gap) {
                    if let thermostat {
                        ThermostatCard(thermostat: thermostat, dialSize: size.height > 1100 ? 120 : 100)
                    }
                    if prefs.showWeather { ForecastCard(hourCount: 6) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func lightsSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Metrics.gap) {
            LightsGrid()
                .frame(maxHeight: .infinity)
            if settings.prefs.showDevices { DevicesRow(width: width) }
            if settings.prefs.showScenes { ScenesRow() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Thermostat keeps its size, now playing sits at the bottom, forecast takes the rest.
    private func sidePanel(size: CGSize) -> some View {
        let prefs = settings.prefs
        // Height left for the dial after the header, the other cards and the gaps.
        let panelHeight = size.height - Metrics.margin * 2 - 72
        let dial = (panelHeight - 440).clamped(to: 90...150)
        return VStack(spacing: Metrics.gap) {
            if let thermostat {
                ThermostatCard(thermostat: thermostat, dialSize: dial)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if prefs.showWeather {
                ForecastCard(hourCount: 5, vertical: true)
            } else {
                Spacer(minLength: 0)
            }
            if prefs.showMusic { NowPlayingCard(twoRows: true) }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Header

    private func header(size: CGSize, landscape: Bool) -> some View {
        let prefs = settings.prefs
        let clockSize: CGFloat = size.height > 1000 ? 52 : 44
        return VStack(alignment: .leading, spacing: Metrics.gap) {
            HStack(alignment: .center, spacing: Metrics.gap) {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(prefs.formatTime(context.date))
                            .font(prefs.clock.font(size: clockSize))
                            .monospacedDigit()
                            .foregroundStyle(prefs.clock.color.color)
                            .lineLimit(1)
                            .fixedSize()
                        if prefs.showDate {
                            Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        // Tap for what's on and how long it's been on.
                        Button {
                            Feedback.tap()
                            showEnergy = true
                        } label: {
                            StatusLine(now: context.date)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        .frame(maxWidth: landscape ? 280 : 420, alignment: .leading)
                    }
                }

                if landscape {
                    RoomPicker()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }

                if prefs.showWeather { WeatherSummary() }

                if home.isDemo {
                    Text("Demo")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .frame(height: Metrics.headerHeight)
                        .glassEffect(.regular, in: .capsule)
                }

                if !recorder.isRecording {
                    AssistantButton(talk: talk) { showAssistant = true }
                    circleButton("gearshape.fill") { showSettings = true }
                }
            }
            .foregroundStyle(.white)

            if let problem = home.authorizationProblem, !home.isDemo {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: Metrics.headerHeight, height: Metrics.headerHeight)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

#Preview(traits: .landscapeLeft) {
    DashboardView()
        .environment(HomeStore())
        .environment(MusicStore())
        .environment(AppSettings())
        .environment(WeatherStore())
        .environment(IdleMonitor())
        .environment(AssistantStore())
        .environment(SceneRecorder())
        .environment(AutomationStore())
}
