//
//  UndoCenter.swift
//  DankHome
//
//  After All Off/On, a scene button or an assistant request, offers "Undo" for a few
//  seconds. Undo puts back only what changed since the snapshot.
//

import SwiftUI

@Observable
final class UndoCenter {
    struct Pending: Identifiable {
        let id = UUID()
        var label: String
        var before: CustomScene
    }

    private(set) var pending: Pending?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    /// Captures the home now, runs `action`, and offers to undo it if anything changed.
    func perform(_ label: String, home: HomeStore, action: () async -> Void) async {
        let before = Self.snapshot(home)
        await action()
        // Give optimistic updates a moment to land before comparing.
        try? await Task.sleep(for: .milliseconds(150))
        guard Self.snapshot(home) != before else { return }
        offer(label, before: before)
    }

    func perform(_ label: String, home: HomeStore, action: () -> Void) {
        let before = Self.snapshot(home)
        action()
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard Self.snapshot(home) != before else { return }
            offer(label, before: before)
        }
    }

    func undo(runner: SceneRunner) {
        guard let pending else { return }
        let home = runner.home
        // Only restore what's different now, so other changes made since are kept.
        var restore = CustomScene()
        restore.lights = pending.before.lights.filter { setting in
            home.lights.first { $0.key == setting.key }?.currentSetting != setting
        }
        restore.devices = pending.before.devices?.filter { setting in
            home.devices.first { $0.key == setting.key }?.currentSetting != setting
        }
        if let thermostat = home.thermostats.first, let before = pending.before.thermostat,
           before.mode != thermostat.mode.rawValue || before.targetC != thermostat.targetC {
            restore.thermostat = before
        }
        runner.run(SceneButton(name: "Undo", symbol: "arrow.uturn.backward", action: .custom(restore)))
        Feedback.success()
        dismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.snappy) { pending = nil }
    }

    private func offer(_ label: String, before: CustomScene) {
        withAnimation(.snappy) { pending = Pending(label: label, before: before) }
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    static func snapshot(_ home: HomeStore) -> CustomScene {
        var scene = CustomScene()
        scene.lights = home.lights.filter(\.isReachable).map(\.currentSetting)
        let devices = home.devices.filter { $0.isControllable && $0.isReachable }.map(\.currentSetting)
        scene.devices = devices.isEmpty ? nil : devices
        if let thermostat = home.thermostats.first {
            scene.thermostat = ThermostatSetting(mode: thermostat.mode.rawValue, targetC: thermostat.targetC)
        }
        return scene
    }
}

struct UndoChip: View {
    @Environment(UndoCenter.self) private var undo
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let pending = undo.pending {
            HStack(spacing: Metrics.inner) {
                Text(pending.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .frame(maxWidth: 320)
                Button {
                    undo.undo(runner: SceneRunner(home: home, music: music, settings: settings))
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.bold))
                        .fixedSize()
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: Metrics.headerHeight - 6)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .frame(height: Metrics.headerHeight + 8)
            .glassEffect(.regular, in: .capsule)
            .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(pending.id)
        }
    }
}
