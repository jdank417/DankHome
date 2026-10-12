//
//  SceneButtonsSettings.swift
//  DankHome
//

import SwiftUI

struct SceneButtonsSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HomeStore.self) private var home
    @State private var newButton: UUID?

    var body: some View {
        let buttons = settings.sceneButtons(home: home)
        Form {
            Section {
                ForEach(buttons) { button in
                    NavigationLink {
                        SceneButtonSetup(buttonID: button.id)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(button.name)
                                Text(button.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: button.symbol)
                        }
                    }
                }
                .onDelete { offsets in settings.editSceneButtons(home: home) { $0.remove(atOffsets: offsets) } }
                .onMove { from, to in settings.editSceneButtons(home: home) { $0.move(fromOffsets: from, toOffset: to) } }

                Button {
                    let button = SceneButton(name: "", symbol: "sparkles", action: .custom(CustomScene()))
                    settings.editSceneButtons(home: home) { $0.append(button) }
                    newButton = button.id
                } label: {
                    Label("New Button", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Buttons")
            } footer: {
                Text(settings.prefs.sceneButtons == nil
                     ? "These are your Home app scenes. Tap one to change it, or make a new button."
                     : "Shown along the bottom of the dashboard. Tap Edit to reorder or delete.")
            }

            if settings.prefs.sceneButtons != nil {
                Section {
                    Button("Reset to Home App Scenes", role: .destructive) {
                        settings.prefs.sceneButtons = nil
                    }
                }
            }
        }
        .navigationTitle("Scene Buttons")
        .toolbar { EditButton() }
        .navigationDestination(item: $newButton) { SceneButtonSetup(buttonID: $0) }
    }
}

/// Setting up a button as three short steps: name it, choose how it works, then
/// record it (or pick a Home scene).
struct SceneButtonSetup: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @Environment(SceneRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    let buttonID: UUID
    /// Typed locally so saving each keystroke can't drop letters mid-word.
    @State private var name = ""
    @State private var editingStep: SceneStep?

    private var button: SceneButton? {
        settings.sceneButtons(home: home).first { $0.id == buttonID }
    }

    private func edit(_ change: (inout SceneButton) -> Void) {
        settings.editSceneButtons(home: home) { buttons in
            if let index = buttons.firstIndex(where: { $0.id == buttonID }) { change(&buttons[index]) }
        }
    }

    var body: some View {
        content
            .onAppear { name = button?.name ?? "" }
            .onChange(of: name) { _, newName in
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if button?.name != trimmed { edit { $0.name = trimmed } }
            }
    }

    @ViewBuilder private var content: some View {
        if let button {
            Form {
                // 1. Name it
                Section {
                    TextField("Movie Night", text: $name)
                        .font(.title3)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                        ForEach(SceneButton.symbols, id: \.self) { symbol in
                            Button {
                                edit { $0.symbol = symbol }
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(symbol == button.symbol ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.06),
                                                in: .rect(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(symbol == button.symbol ? Color.accentColor : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    StepHeader(number: 1, title: "Name it")
                }

                // 2. How it works
                Section {
                    HStack(spacing: 12) {
                        choiceCard(title: "Record what I do", detail: "Set things up on the dashboard and DankHome remembers.",
                                   symbol: "record.circle", selected: isCustom(button)) {
                            if !isCustom(button) { edit { $0.action = .custom(CustomScene()) } }
                        }
                        choiceCard(title: "Run a Home scene", detail: "Use a scene you made in the Home app.",
                                   symbol: "house.fill", selected: !isCustom(button)) {
                            if isCustom(button) { edit { $0.action = .homeScene(name: home.scenes.first?.name ?? "") } }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    StepHeader(number: 2, title: "Choose how it works")
                }

                // 3. Record or pick
                switch button.action {
                case .custom(let scene):
                    recordSection(button, scene: scene)
                case .homeScene(let name):
                    Section {
                        ForEach(home.scenes) { scene in
                            Button {
                                edit { $0.action = .homeScene(name: scene.name) }
                            } label: {
                                HStack {
                                    Label(scene.name, systemImage: scene.symbol)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if scene.name == name {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                        if home.scenes.isEmpty {
                            Text("No scenes yet. Make one in the Home app.").foregroundStyle(.secondary)
                        }
                    } header: {
                        StepHeader(number: 3, title: "Pick the scene")
                    }
                }

                Section {
                    Button {
                        Feedback.press()
                        SceneRunner(home: home, music: music, settings: settings).run(button)
                    } label: {
                        Label("Try It Now", systemImage: "play.fill")
                    }
                    .disabled(button.summary == "Does nothing yet")
                    Button("Delete Button", role: .destructive) {
                        settings.editSceneButtons(home: home) { $0.removeAll { $0.id == buttonID } }
                        dismiss()
                    }
                }
            }
            .navigationTitle(button.name.isEmpty ? "New Button" : button.name)
            .sheet(item: $editingStep) { step in
                StepEditor(step: step, scene: customScene)
            }
        }
    }

    /// The button's custom steps, editable.
    private var customScene: Binding<CustomScene> {
        Binding(
            get: {
                if case .custom(let scene) = settings.sceneButtons(home: home).first(where: { $0.id == buttonID })?.action {
                    return scene
                }
                return CustomScene()
            },
            set: { scene in edit { $0.action = .custom(scene) } }
        )
    }

    @ViewBuilder
    private func recordSection(_ button: SceneButton, scene: CustomScene) -> some View {
        let steps = SceneStep.steps(for: scene, unit: settings.prefs, home: home)
        Section {
            if steps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tap Start Recording, then set your lights, thermostat and music on the dashboard exactly how you want them. Tap Done when you're finished.")
                        .foregroundStyle(.secondary)
                    recordButton(button, title: "Start Recording")
                }
                .padding(.vertical, 6)
                AddStepButton(scene: customScene) { editingStep = $0 }
            } else {
                SceneStepList(steps: steps, onEdit: { editingStep = $0 }) { step in
                    edit {
                        guard case .custom(var scene) = $0.action else { return }
                        SceneStep.remove(step, from: &scene)
                        $0.action = .custom(scene)
                    }
                }
                AddStepButton(scene: customScene) { editingStep = $0 }
                recordButton(button, title: "Record Again")
            }
        } header: {
            StepHeader(number: 3, title: steps.isEmpty ? "Record it" : "When tapped, it will")
        } footer: {
            if !steps.isEmpty { Text("Tap a step to change it. Swipe left on a step to remove it.") }
        }
    }

    private func recordButton(_ button: SceneButton, title: String) -> some View {
        Button {
            if name.isEmpty { name = "New Button" }
            edit { $0.name = name }
            recorder.start(buttonID: button.id, name: name, home: home, music: music)
        } label: {
            Label(title, systemImage: "record.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    private func isCustom(_ button: SceneButton) -> Bool {
        if case .custom = button.action { true } else { false }
    }

    private func choiceCard(title: String, detail: String, symbol: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(selected ? Color.accentColor : .primary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                }
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Selection shows as a soft fill; an outline gets clipped by the list's corners.
            .background(selected ? Color.accentColor.opacity(0.18) : Color(white: 0.17), in: .rect(cornerRadius: 22))
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

/// Numbered step title: ① Name it.
private struct StepHeader: View {
    var number: Int
    var title: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: .circle)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
        }
    }
}
