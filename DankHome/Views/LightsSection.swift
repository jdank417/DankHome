//
//  LightsSection.swift
//  DankHome
//

import SwiftUI

struct RoomPicker: View {
    @Environment(HomeStore.self) private var home

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    chip("All Rooms", room: nil)
                    ForEach(home.roomNames, id: \.self) { chip($0, room: $0) }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, room: String?) -> some View {
        let selected = home.selectedRoom == room
        return Button {
            withAnimation(.snappy) { home.selectedRoom = room }
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.white).interactive() : .regular.interactive(), in: .capsule)
    }
}

struct LightsGrid: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    @Environment(IdleMonitor.self) private var idle
    @State private var detailLight: Light?

    private var columns: [GridItem] {
        let size = settings.prefs.tileSize
        return [GridItem(.adaptive(minimum: size.minWidth, maximum: size.minWidth * 1.4), spacing: 16)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle(title: "Lights", symbol: "lightbulb.fill")
                Text("Hold a light for color")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.leading, 8)
                Spacer()
                Text("\(home.lightsOnCount) of \(home.visibleLights.count) on")
                    .foregroundStyle(.white.opacity(0.6))
                Button {
                    home.setAllVisible(on: home.lightsOnCount == 0)
                } label: {
                    Label(home.lightsOnCount == 0 ? "All On" : "All Off",
                          systemImage: home.lightsOnCount == 0 ? "lightbulb.max.fill" : "power")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
            }

            if home.visibleLights.isEmpty {
                ContentUnavailableView("No Lights", systemImage: "lightbulb.slash",
                                       description: Text("Add lights to this room in the Home app."))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(home.visibleLights) { light in
                        LightTile(light: light, showsRoom: home.selectedRoom == nil) {
                            detailLight = light
                        }
                    }
                }
            }
        }
        .sheet(item: $detailLight) { light in
            LightDetailView(lightID: light.id)
                .presentationDetents([.large])
        }
        .onChange(of: idle.isSleeping) { _, sleeping in
            if sleeping { detailLight = nil }
        }
    }
}

/// Tap to toggle, swipe sideways to dim, long-press for color and fine control.
struct LightTile: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    var light: Light
    var showsRoom: Bool
    var onLongPress: () -> Void

    @State private var dragStart: Double?

    private var level: Double { light.isOn ? (light.brightness ?? 100) / 100 : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: light.isOn ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(light.isOn ? light.tint : .white.opacity(0.5))
                    .shadow(color: light.isOn ? light.tint.opacity(0.8) : .clear, radius: 12)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.white.opacity(light.isOn ? 0.9 : 0.1)))
                Spacer()
                if !light.isReachable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
            }
            Spacer(minLength: 16)
            Text(light.name)
                .font(.headline)
                .lineLimit(2)
            if showsRoom {
                Text(light.roomName)
                    .font(.subheadline)
                    .opacity(0.65)
            }
            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .opacity(0.8)
                .contentTransition(.numericText())
            if light.isOn, light.brightness != nil {
                GeometryReader { proxy in
                    Capsule().fill(.black.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(light.tint.mix(with: .black, by: 0.25))
                                .frame(width: max(proxy.size.width * level, 6))
                        }
                }
                .frame(height: 6)
                .padding(.top, 8)
            }
        }
        .foregroundStyle(light.isOn ? .black : .white)
        .padding(18)
        .frame(height: settings.prefs.tileSize.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if light.isOn {
                Rectangle()
                    .fill(.white.opacity(0.92))
                    .overlay(light.tint.opacity(0.22))
            }
        }
        .clipShape(.rect(cornerRadius: 28))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
        .opacity(light.isReachable ? 1 : 0.55)
        .contentShape(.rect(cornerRadius: 28))
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy) { home.toggle(light) }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPress()
        }
        .simultaneousGesture(dimGesture)
        .animation(.snappy, value: light)
    }

    private var statusText: String {
        guard light.isReachable else { return "No Response" }
        guard light.isOn else { return "Off" }
        if let brightness = light.brightness { return "\(Int(brightness))%" }
        return "On"
    }

    private var dimGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard light.brightness != nil,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                let start = dragStart ?? (light.isOn ? light.brightness ?? 100 : 0)
                dragStart = start
                home.setBrightness(start + value.translation.width / 2, for: light.id, commit: false)
            }
            .onEnded { _ in
                guard dragStart != nil else { return }
                dragStart = nil
                let current = home.lights.first { $0.id == light.id }?.brightness ?? 0
                home.setBrightness(light.isOn ? current : 0, for: light.id, commit: true)
            }
    }
}

struct LightDetailView: View {
    @Environment(HomeStore.self) private var home
    @Environment(\.dismiss) private var dismiss
    var lightID: UUID

    @State private var dragStart: Double?

    private static let colors: [(hue: Double, saturation: Double)] = [
        (0, 85), (25, 90), (45, 85), (60, 80), (120, 70), (175, 80), (200, 85), (230, 80), (275, 75), (320, 70),
    ]
    private static let whites: [Double] = [2200, 2700, 3000, 4000, 5000, 6500]

    var body: some View {
        if let light = home.lights.first(where: { $0.id == lightID }) {
            VStack(spacing: 32) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(light.name).font(.largeTitle.bold())
                        Text(light.roomName).font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.glass)
                }

                Spacer()

                if light.brightness != nil {
                    brightnessSlider(light)
                } else {
                    Button {
                        home.toggle(light)
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 64, weight: .semibold))
                            .frame(width: 180, height: 180)
                    }
                    .buttonStyle(.glass)
                    .tint(light.isOn ? light.tint : .gray)
                }

                Text(light.isOn ? "\(Int(light.brightness ?? 100))%" : "Off")
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .contentTransition(.numericText())

                if light.colorTemperature != nil || light.supportsColor {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("White").font(.headline).foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            ForEach(Self.whites, id: \.self) { kelvin in
                                Button {
                                    withAnimation { home.setWhite(kelvin: kelvin, for: light.id) }
                                } label: {
                                    VStack(spacing: 6) {
                                        Circle()
                                            .fill(Light.white(kelvin: kelvin))
                                            .frame(width: 52, height: 52)
                                            .overlay(Circle().stroke(.white, lineWidth: isSelectedWhite(kelvin, light) ? 4 : 0).padding(-5))
                                        Text(verbatim: "\(Int(kelvin))K").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if light.supportsColor {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color").font(.headline).foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            ForEach(Self.colors.indices, id: \.self) { index in
                                let swatch = Self.colors[index]
                                Button {
                                    withAnimation { home.setColor(hue: swatch.hue, saturation: swatch.saturation, for: light.id) }
                                } label: {
                                    Circle()
                                        .fill(Color(hue: swatch.hue / 360, saturation: swatch.saturation / 100, brightness: 1))
                                        .frame(width: 52, height: 52)
                                        .overlay(Circle().stroke(.white, lineWidth: isSelected(swatch, light) ? 4 : 0).padding(-5))
                                }
                                .buttonStyle(.plain)
                            }
                            ColorPicker("Any Color", selection: Binding(
                                get: { light.tint },
                                set: { home.setColor($0, for: light.id) }
                            ), supportsOpacity: false)
                            .labelsHidden()
                            .scaleEffect(1.5)
                            .padding(.leading, 8)
                        }
                    }
                }
                Spacer()
            }
            .padding(40)
            .animation(.snappy, value: light)
        }
    }

    private func isSelected(_ swatch: (hue: Double, saturation: Double), _ light: Light) -> Bool {
        !light.usesWhite && abs((light.hue ?? -1) - swatch.hue) < 1 && abs((light.saturation ?? -1) - swatch.saturation) < 1
    }

    private func isSelectedWhite(_ kelvin: Double, _ light: Light) -> Bool {
        guard light.usesWhite, let mireds = light.colorTemperature else { return false }
        return abs(1_000_000 / mireds - kelvin) < 150
    }

    private func brightnessSlider(_ light: Light) -> some View {
        let level = light.isOn ? (light.brightness ?? 100) / 100 : 0
        let height: CGFloat = 380
        return ZStack(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.12))
            Rectangle()
                .fill(light.tint.gradient)
                .frame(height: height * level)
            Image(systemName: light.isOn ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 34))
                .foregroundStyle(light.isOn ? .black.opacity(0.6) : .white.opacity(0.6))
                .padding(.bottom, 28)
        }
        .frame(width: 150, height: height)
        .clipShape(.rect(cornerRadius: 44))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dragStart ?? level * 100
                    dragStart = start
                    home.setBrightness(start - Double(value.translation.height / height) * 100, for: light.id, commit: false)
                }
                .onEnded { _ in
                    dragStart = nil
                    let current = home.lights.first { $0.id == light.id }
                    home.setBrightness(current?.isOn == true ? current?.brightness ?? 0 : 0, for: light.id, commit: true)
                }
        )
    }
}

struct ScenesRow: View {
    @Environment(HomeStore.self) private var home

    var body: some View {
        if !home.scenes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Scenes", symbol: "sparkles")
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            ForEach(home.scenes) { scene in
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    withAnimation(.snappy) { home.run(scene) }
                                } label: {
                                    Label(scene.name, systemImage: scene.symbol)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 22)
                                        .padding(.vertical, 16)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}
