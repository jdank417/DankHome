//
//  DankHomeApp.swift
//  DankHome
//
//  Created by Jason Dank on 10/8/26.
//

import AppIntents
import SwiftUI

@main
struct DankHomeApp: App {
    // Shared so Siri and Shortcuts requests reach the same home and settings.
    @State private var home = AppStores.shared.home
    @State private var music = AppStores.shared.music
    @State private var settings = AppStores.shared.settings
    @State private var weather = AppStores.shared.weather
    @State private var idle = AppStores.shared.idle
    @State private var assistant = AppStores.shared.assistant
    @State private var recorder = AppStores.shared.recorder
    @State private var automation = AppStores.shared.automation

    static let isPhone = UIDevice.current.userInterfaceIdiom == .phone

    var body: some Scene {
        WindowGroup {
            ZStack {
                // The iPhone gets its own scrolling layout; the iPad dashboard needs a big screen.
                if Self.isPhone {
                    PhoneDashboardView()
                } else {
                    DashboardView()
                }
                if idle.isSleeping, !Self.isPhone {
                    NightClockView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .background(ActivityTracker(monitor: idle))
            .environment(home)
            .environment(music)
            .environment(settings)
            .environment(weather)
            .environment(idle)
            .environment(assistant)
            .environment(recorder)
            .environment(automation)
            .fontDesign(settings.prefs.appFont.design)
            .tint(settings.prefs.accent.color)
            .task { assistant.prewarm() }
            // Keep Siri's list of button names current.
            .onChange(of: settings.sceneButtons(home: home).map(\.name), initial: true) {
                DankHomeShortcuts.updateAppShortcutParameters()
            }
            .onChange(of: settings.prefs.demoMode, initial: true) { _, demo in
                home.forceDemo = demo
            }
            .onChange(of: settings.prefs.keepAwake, initial: true) { _, keepAwake in
                // Wall-mounted: keep the screen awake while the app is open.
                // A phone in a pocket should still lock.
                UIApplication.shared.isIdleTimerDisabled = keepAwake && !Self.isPhone
            }
            // Re-fetch weather every 30 minutes, and right away when its settings change.
            .task(id: settings.prefs.weatherKey) {
                while !Task.isCancelled {
                    await weather.refresh(settings.prefs)
                    try? await Task.sleep(for: .seconds(30 * 60))
                }
            }
            // Timers, routines, the wake-up light and adaptive lighting.
            .task {
                while !Task.isCancelled {
                    await automation.tick()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
            // Check for idle every few seconds to start the night clock.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    if !Self.isPhone { idle.check(settings.prefs) }
                }
            }
        }
    }
}
