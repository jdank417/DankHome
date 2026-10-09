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

    var body: some Scene {
        WindowGroup {
            ZStack {
                DashboardView()
                if idle.isSleeping {
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
                UIApplication.shared.isIdleTimerDisabled = keepAwake
            }
            // Re-fetch weather every 30 minutes, and right away when its settings change.
            .task(id: settings.prefs.weatherKey) {
                while !Task.isCancelled {
                    await weather.refresh(settings.prefs)
                    try? await Task.sleep(for: .seconds(30 * 60))
                }
            }
            // Check for idle every few seconds to start the night clock.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    idle.check(settings.prefs)
                }
            }
        }
    }
}
