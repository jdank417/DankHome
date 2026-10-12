//
//  LightDetailView.swift
//  DankHome
//

import SwiftUI

/// Brightness, a color wheel and quick colors for one light. Sizes itself to the sheet:
/// three columns when wide, stacked when tall — nothing is ever cut off.
struct LightDetailView: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var lightID: UUID

    @State private var dragStart: Double?

    private static let colors: [(hue: Double, saturation: Double)] = [
        (0, 85), (25, 90), (45, 85), (60, 80), (120, 70), (175, 80), (200, 85), (230, 80), (275, 75), (320, 70),
    ]
    private static let whites: [Double] = [2200, 2700, 3000, 4000, 5000, 6500]

    var body: some View {
        if let light = home.lights.first(where: { $0.id == lightID }) {
            VStack(spacing: 24) {
                header(light)
                GeometryReader { proxy in
                    let size = proxy.size
                    if size.width > size.height * 1.2 {
                        wideLayout(light, size: size)
                    } else {
                        tallLayout(light, size: size)
                    }
                }
            }
            .padding(32)
            .animation(.snappy, value: light)
        }
    }

    // MARK: Layouts

    /// Landscape: brightness · wheel · swatches.
    private func wideLayout(_ light: Light, size: CGSize) -> some View {
        let control = min(size.height - 56, (size.width - 64) * 0.42)
        return HStack(alignment: .center, spacing: 32) {
            brightnessColumn(light, height: control)
            if light.supportsColor {
                ColorWheel(hue: light.hue ?? 0, saturation: light.saturation ?? 0,
                           showsThumb: !light.usesWhite && light.isOn) { hue, saturation in
                    home.setColor(hue: hue, saturation: saturation, for: light.id)
                }
                .frame(width: control, height: control)
            }
            swatches(light)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Portrait: brightness and wheel side by side, swatches underneath.
    private func tallLayout(_ light: Light, size: CGSize) -> some View {
        let control = min(size.height * 0.5, (size.width - 32) * 0.55)
        return VStack(spacing: 28) {
            HStack(alignment: .center, spacing: 32) {
                brightnessColumn(light, height: control)
                if light.supportsColor {
                    ColorWheel(hue: light.hue ?? 0, saturation: light.saturation ?? 0,
                               showsThumb: !light.usesWhite && light.isOn) { hue, saturation in
                        home.setColor(hue: hue, saturation: saturation, for: light.id)
                    }
                    .frame(width: control, height: control)
                }
            }
            swatches(light)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Pieces

    private func header(_ light: Light) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(light.name).font(.largeTitle.bold())
                Text(light.roomName).font(.title3).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                Feedback.tap()
                let saved = settings.prefs.lightOrder.isEmpty ? settings.prefs.pinnedLights : settings.prefs.lightOrder
                var order = GridReorder.sorted(home.lights, by: saved, key: \.key).map(\.key)
                order.removeAll { $0 == light.key }
                order.insert(light.key, at: 0)
                withAnimation(.snappy) { settings.prefs.lightOrder = order }
            } label: {
                Label("Move to Top", systemImage: "arrow.up.to.line")
                    .fixedSize()
            }
            .buttonStyle(.glass)
            Button("Done") { dismiss() }
                .buttonStyle(.glass)
                .fixedSize()
        }
    }

    private func brightnessColumn(_ light: Light, height: CGFloat) -> some View {
        VStack(spacing: 12) {
            if light.brightness != nil {
                brightnessSlider(light, height: height - 52)
            } else {
                Button {
                    home.toggle(light)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 56, weight: .semibold))
                        .frame(width: height * 0.4, height: height * 0.4)
                }
                .buttonStyle(.glass)
                .tint(light.isOn ? light.tint : .gray)
            }
            Text(light.isOn ? "\(Int(light.brightness ?? 100))%" : "Off")
                .font(.system(size: 32, weight: .light, design: .rounded))
                .contentTransition(.numericText())
                .frame(height: 40)
        }
    }

    /// Whites and favorite colors as grids that wrap to the space they get.
    @ViewBuilder
    private func swatches(_ light: Light) -> some View {
        let grid = [GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 14)]
        VStack(alignment: .leading, spacing: 20) {
            if light.colorTemperature != nil || light.supportsColor {
                VStack(alignment: .leading, spacing: 10) {
                    Text("White").font(.headline).foregroundStyle(.secondary)
                    LazyVGrid(columns: grid, spacing: 14) {
                        ForEach(Self.whites, id: \.self) { kelvin in
                            Button {
                                Feedback.tap()
                                withAnimation { home.setWhite(kelvin: kelvin, for: light.id) }
                            } label: {
                                VStack(spacing: 4) {
                                    swatchCircle(Light.white(kelvin: kelvin), selected: isSelectedWhite(kelvin, light))
                                    Text(verbatim: "\(Int(kelvin))K").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if light.supportsColor {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Favorites").font(.headline).foregroundStyle(.secondary)
                    LazyVGrid(columns: grid, spacing: 14) {
                        ForEach(Self.colors.indices, id: \.self) { index in
                            let swatch = Self.colors[index]
                            Button {
                                Feedback.tap()
                                withAnimation { home.setColor(hue: swatch.hue, saturation: swatch.saturation, for: light.id) }
                            } label: {
                                swatchCircle(Color(hue: swatch.hue / 360, saturation: swatch.saturation / 100, brightness: 1),
                                             selected: isSelected(swatch, light))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func swatchCircle(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 52)
            .overlay(Circle().stroke(.white, lineWidth: selected ? 3 : 0).padding(-4))
            .padding(4)
    }

    private func isSelected(_ swatch: (hue: Double, saturation: Double), _ light: Light) -> Bool {
        !light.usesWhite && abs((light.hue ?? -1) - swatch.hue) < 1 && abs((light.saturation ?? -1) - swatch.saturation) < 1
    }

    private func isSelectedWhite(_ kelvin: Double, _ light: Light) -> Bool {
        guard light.usesWhite, let mireds = light.colorTemperature else { return false }
        return abs(1_000_000 / mireds - kelvin) < 150
    }

    private func brightnessSlider(_ light: Light, height: CGFloat) -> some View {
        let level = light.isOn ? (light.brightness ?? 100) / 100 : 0
        return ZStack(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.12))
            Rectangle()
                .fill(light.tint.gradient)
                .frame(height: height * level)
            Image(systemName: light.isOn ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 30))
                .foregroundStyle(light.isOn ? .black.opacity(0.6) : .white.opacity(0.6))
                .padding(.bottom, 24)
        }
        .frame(width: min(140, height * 0.42), height: height)
        .clipShape(.rect(cornerRadius: 40))
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
