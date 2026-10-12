//
//  RoomColorView.swift
//  DankHome
//

import SwiftUI

/// Color, white and brightness for every light being shown (the selected room, or all).
struct RoomColorView: View {
    @Environment(HomeStore.self) private var home
    @Environment(\.dismiss) private var dismiss
    @State private var picked: (hue: Double, saturation: Double)?
    @State private var level: Double?

    private static let whites: [Double] = [2200, 2700, 3000, 4000, 5000, 6500]
    private static let colors: [(hue: Double, saturation: Double)] = [
        (0, 85), (25, 90), (45, 85), (60, 80), (120, 70), (175, 80), (200, 85), (230, 80), (275, 75), (320, 70),
    ]

    private var lights: [Light] { home.visibleLights.filter(\.isReachable) }
    private var colorLights: [Light] { lights.filter(\.supportsColor) }
    private var whiteLights: [Light] { lights.filter { $0.colorTemperature != nil || $0.supportsColor } }
    private var dimmable: [Light] { lights.filter { $0.brightness != nil } }

    /// Starting values come from the first light that's on in color.
    private var shownColor: (hue: Double, saturation: Double) {
        if let picked { return picked }
        let light = colorLights.first { $0.isOn && !$0.usesWhite }
        return (light?.hue ?? 0, light?.saturation ?? 0)
    }

    private var shownLevel: Double {
        if let level { return level }
        let on = dimmable.filter(\.isOn)
        guard !on.isEmpty else { return 100 }
        return on.compactMap(\.brightness).reduce(0, +) / Double(on.count)
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(home.selectedRoom ?? "All Rooms").font(.largeTitle.bold())
                    Text(summary).font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.glass)
            }
            GeometryReader { proxy in
                let wide = proxy.size.width > proxy.size.height * 1.2
                let wheel = min(wide ? proxy.size.height - 20 : proxy.size.height * 0.5, proxy.size.width * (wide ? 0.42 : 0.7))
                let layout = wide ? AnyLayout(HStackLayout(spacing: 40)) : AnyLayout(VStackLayout(spacing: 28))
                layout {
                    if !colorLights.isEmpty {
                        ColorWheel(hue: shownColor.hue, saturation: shownColor.saturation,
                                   showsThumb: picked != nil || colorLights.contains { $0.isOn && !$0.usesWhite }) { hue, saturation in
                            picked = (hue, saturation)
                            for light in colorLights { home.setColor(hue: hue, saturation: saturation, for: light.id) }
                        }
                        .frame(width: wheel, height: wheel)
                    }
                    controls
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: wide ? .center : .top)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .padding(32)
        .preferredColorScheme(.dark)
    }

    private var summary: String {
        let count = lights.count
        return count == 1 ? "1 light" : "\(count) lights"
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !dimmable.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Brightness").font(.headline).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Image(systemName: "sun.min").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { shownLevel }, set: { value in
                            level = value
                            for light in dimmable { home.setBrightness(value, for: light.id, commit: false) }
                        }), in: 1...100) { editing in
                            guard !editing, let level else { return }
                            for light in dimmable { home.setBrightness(level, for: light.id, commit: true) }
                        }
                        Text("\(Int(shownLevel))%")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            let grid = [GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 14)]
            if !whiteLights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("White").font(.headline).foregroundStyle(.secondary)
                    LazyVGrid(columns: grid, spacing: 14) {
                        ForEach(Self.whites, id: \.self) { kelvin in
                            swatch(Light.white(kelvin: kelvin), label: "\(Int(kelvin))K") {
                                picked = nil
                                for light in whiteLights { home.setWhite(kelvin: kelvin, for: light.id) }
                            }
                        }
                    }
                }
            }
            if !colorLights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Favorites").font(.headline).foregroundStyle(.secondary)
                    LazyVGrid(columns: grid, spacing: 14) {
                        ForEach(Self.colors.indices, id: \.self) { index in
                            let color = Self.colors[index]
                            swatch(Color(hue: color.hue / 360, saturation: color.saturation / 100, brightness: 1)) {
                                picked = color
                                for light in colorLights { home.setColor(hue: color.hue, saturation: color.saturation, for: light.id) }
                            }
                        }
                    }
                }
            }
            if colorLights.isEmpty, !whiteLights.isEmpty || !dimmable.isEmpty {
                Text("None of these lights can show colors.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func swatch(_ color: Color, label: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            Feedback.tap()
            withAnimation { action() }
        } label: {
            VStack(spacing: 4) {
                Circle().fill(color).aspectRatio(1, contentMode: .fit).frame(maxWidth: 52)
                if let label { Text(verbatim: label).font(.caption2).foregroundStyle(.secondary) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
