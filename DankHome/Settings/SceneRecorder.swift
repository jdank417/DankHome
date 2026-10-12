//
//  SceneRecorder.swift
//  DankHome
//

import MusicKit
import SwiftUI

/// Records a custom button by watching what the person does on the dashboard.
/// At the end it keeps every light, thermostat setting and music change that was
/// touched or differs from when recording started.
@Observable
final class SceneRecorder {
    struct Session {
        var buttonID: UUID
        var name: String
        var startLights: [String: LightSetting]
        var startDevices: [String: DeviceSetting]
        var startThermostat: Thermostat?
        var startPlaying: Bool
    }

    /// The result waiting to be reviewed and saved.
    struct Review: Identifiable {
        var id: UUID { buttonID }
        var buttonID: UUID
        var name: String
        var scene: CustomScene
    }

    private(set) var session: Session?
    var review: Review?
    var isRecording: Bool { session != nil }

    func start(buttonID: UUID, name: String, home: HomeStore, music: MusicStore) {
        session = Session(
            buttonID: buttonID,
            name: name,
            startLights: Dictionary(home.lights.map { ($0.key, $0.currentSetting) }, uniquingKeysWith: { first, _ in first }),
            startDevices: Dictionary(home.devices.map { ($0.key, $0.currentSetting) }, uniquingKeysWith: { first, _ in first }),
            startThermostat: home.thermostats.first,
            startPlaying: music.player.state.playbackStatus == .playing
        )
        home.touched = []
        music.touched = false
    }

    func finish(home: HomeStore, music: MusicStore) {
        guard let session else { return }
        let touched = home.touched ?? []
        var scene = CustomScene()

        for light in home.lights where light.isReachable {
            let final = light.currentSetting
            guard touched.contains(light.id) || session.startLights[light.key] != final else { continue }
            scene.lights.append(final.on ? final : LightSetting(key: light.key, on: false))
        }
        var devices: [DeviceSetting] = []
        for device in home.devices where device.isControllable && device.isReachable {
            let final = device.currentSetting
            if touched.contains(device.id) || session.startDevices[device.key] != final { devices.append(final) }
        }
        if !devices.isEmpty { scene.devices = devices }
        if let thermostat = home.thermostats.first,
           touched.contains(thermostat.id)
            || thermostat.mode != session.startThermostat?.mode
            || thermostat.targetC != session.startThermostat?.targetC {
            scene.thermostat = ThermostatSetting(mode: thermostat.mode.rawValue,
                                                 targetC: thermostat.mode == .off ? nil : thermostat.targetC)
        }
        let playing = music.player.state.playbackStatus == .playing
        if music.touched || playing != session.startPlaying {
            scene.music = playing ? .play : .pause
        }

        review = Review(buttonID: session.buttonID, name: session.name, scene: scene)
        stopTracking(home: home, music: music)
    }

    func cancel(home: HomeStore, music: MusicStore) {
        stopTracking(home: home, music: music)
    }

    private func stopTracking(home: HomeStore, music: MusicStore) {
        home.touched = nil
        music.touched = false
        session = nil
    }
}

/// Floating bar shown on the dashboard while recording.
struct RecordingBanner: View {
    @Environment(SceneRecorder.self) private var recorder
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @State private var pulse = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(spacing: Metrics.inner) {
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
                .onAppear { pulse = true }
            VStack(alignment: .leading, spacing: 1) {
                Text("Recording “\(recorder.session?.name ?? "")”")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(sizeClass == .compact ? "Set things how you want them."
                     : "Set lights, devices, the thermostat and music how you want them. Hold a light for color.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Cancel") { recorder.cancel(home: home, music: music) }
                .buttonStyle(.glass)
            Button {
                recorder.finish(home: home, music: music)
            } label: {
                Text("Done").fontWeight(.semibold)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Metrics.cardPadding)
        .frame(height: Metrics.headerHeight + 18)
        .glassEffect(.regular.tint(.red.opacity(0.25)), in: .capsule)
    }
}

/// "Here's what your button will do" — shown after recording.
struct RecordingReviewView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @Environment(SceneRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State var review: SceneRecorder.Review
    @State private var editing: SceneStep?

    var body: some View {
        let steps = SceneStep.steps(for: review.scene, unit: settings.prefs, home: home)
        NavigationStack {
            List {
                Section {
                    if steps.isEmpty {
                        Label("Nothing was changed while recording.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        SceneStepList(steps: steps, onEdit: { editing = $0 }) { SceneStep.remove($0, from: &review.scene) }
                    }
                    AddStepButton(scene: $review.scene) { editing = $0 }
                } header: {
                    Text("When tapped, \(review.name) will")
                } footer: {
                    Text("Tap a step to change it. Swipe left on a step to remove it. Then save.")
                }

                Section {
                    Button {
                        let id = review.buttonID
                        let name = review.name
                        dismiss()
                        recorder.start(buttonID: id, name: name, home: home, music: music)
                    } label: {
                        Label("Record Again", systemImage: "record.circle")
                    }
                }
            }
            .navigationTitle("Review")
            .sheet(item: $editing) { step in
                StepEditor(step: step, scene: $review.scene)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let scene = review.scene
                        settings.editSceneButtons(home: home) { buttons in
                            if let index = buttons.firstIndex(where: { $0.id == review.buttonID }) {
                                buttons[index].action = .custom(scene)
                            }
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(steps.isEmpty)
                }
            }
        }
    }
}
