//
//  NightClockView.swift
//  DankHome
//

import MusicKit
import SwiftUI

/// Tracks touches anywhere in the window and reports when the panel has been idle.
@Observable
final class IdleMonitor {
    private(set) var isSleeping = false
    @ObservationIgnored private var lastActivity = Date.now
    @ObservationIgnored fileprivate weak var window: UIWindow?
    @ObservationIgnored private var savedBrightness: CGFloat?

    func registerActivity() {
        lastActivity = .now
        if isSleeping { wake() }
    }

    /// Called periodically; falls asleep once the idle time has passed.
    func check(_ prefs: Preferences) {
        guard prefs.nightEnabled, !isSleeping,
              Date.now.timeIntervalSince(lastActivity) >= Double(prefs.nightIdleMinutes) * 60 else { return }
        sleep(prefs)
    }

    func sleep(_ prefs: Preferences) {
        guard !isSleeping else { return }
        withAnimation(.easeInOut(duration: 1.2)) { isSleeping = true }
        if prefs.nightDimsScreen, let screen = window?.windowScene?.screen {
            savedBrightness = screen.brightness
            screen.brightness = prefs.nightScreenLevel
        }
    }

    func wake() {
        lastActivity = .now
        withAnimation(.easeOut(duration: 0.4)) { isSleeping = false }
        if let savedBrightness, let screen = window?.windowScene?.screen {
            screen.brightness = savedBrightness
        }
        savedBrightness = nil
    }
}

/// Installs a pass-through touch recognizer on the window so any touch counts as activity.
struct ActivityTracker: UIViewRepresentable {
    var monitor: IdleMonitor

    func makeUIView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.monitor = monitor
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: TrackerView, context: Context) {}

    final class TrackerView: UIView, UIGestureRecognizerDelegate {
        weak var monitor: IdleMonitor?
        private var installed = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !installed else { return }
            installed = true
            monitor?.window = window
            let recognizer = TouchRecognizer { [weak self] in self?.monitor?.registerActivity() }
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    final class TouchRecognizer: UIGestureRecognizer {
        let onTouch: () -> Void

        init(onTouch: @escaping () -> Void) {
            self.onTouch = onTouch
            super.init(target: nil, action: nil)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            onTouch()
            state = .failed
        }
    }
}

/// Dim full-screen clock shown when the panel is idle. Drifts slightly each minute
/// so a wall-mounted screen doesn't burn in.
struct NightClockView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WeatherStore.self) private var weather
    @Environment(IdleMonitor.self) private var idle
    @ObservedObject private var queue = SystemMusicPlayer.shared.queue
    @ObservedObject private var state = SystemMusicPlayer.shared.state

    var body: some View {
        let prefs = settings.prefs
        TimelineView(.everyMinute) { context in
            let drift = Self.drift(for: context.date)
            VStack(spacing: 12) {
                Text(prefs.formatTime(context.date))
                    .font(prefs.nightClock.font(size: 200))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                if prefs.nightShowDate {
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.title.weight(.medium))
                }
                HStack(spacing: 28) {
                    if prefs.nightShowWeather, let current = weather.current {
                        Label(prefs.formatTemperature(celsius: current.temperature),
                              systemImage: WeatherCode.symbol(current.code, isDay: current.isDay))
                    }
                    if prefs.nightShowMusic, state.playbackStatus == .playing, let entry = queue.currentEntry {
                        Label("\(entry.title)\(entry.subtitle.map { " · \($0)" } ?? "")", systemImage: "music.note")
                            .lineLimit(1)
                    }
                }
                .font(.title2)
                .opacity(0.8)
            }
            .foregroundStyle(prefs.nightClock.color.color)
            .opacity(prefs.nightBrightness)
            .padding(60)
            .offset(drift)
            .animation(.easeInOut(duration: 3), value: drift)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture { idle.wake() }
    }

    private static func drift(for date: Date) -> CGSize {
        let minute = Int(date.timeIntervalSince1970 / 60)
        let angle = Double(minute % 12) / 12 * 2 * .pi
        return CGSize(width: cos(angle) * 30, height: sin(angle * 2) * 20)
    }
}
