//
//  LightsSection.swift
//  DankHome
//

import SwiftUI

struct LightsGrid: View {
    @Environment(HomeStore.self) private var home
    @Environment(IdleMonitor.self) private var idle
    @Environment(AppSettings.self) private var settings
    @State private var detailLight: Light?

    /// The saved arrangement (older versions pinned lights instead).
    private var savedOrder: [String] {
        settings.prefs.lightOrder.isEmpty ? settings.prefs.pinnedLights : settings.prefs.lightOrder
    }

    private var orderedLights: [Light] {
        GridReorder.sorted(home.visibleLights, by: savedOrder, key: \.key)
    }

    private let spacing = Metrics.gap

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.gap) {
            LightsHeader()

            if home.visibleLights.isEmpty {
                ContentUnavailableView("No Lights", systemImage: "lightbulb.slash",
                                       description: Text("Add lights to this room in the Home app."))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let fit = Self.fit(count: home.visibleLights.count, in: proxy.size, spacing: spacing)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: fit.columns),
                              spacing: spacing) {
                        ForEach(orderedLights) { light in
                            LightTile(light: light, showsRoom: home.selectedRoom == nil, height: fit.height) {
                                detailLight = light
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $detailLight) { light in
            LightDetailView(lightID: light.id)
                .presentationSizing(.page)
        }
        .onChange(of: idle.isSleeping) { _, sleeping in
            if sleeping { detailLight = nil }
        }
    }

    /// Picks the column count giving the largest tiles that all fit — never scrolls.
    /// Tiles fill the height exactly unless that would make them taller than wide.
    static func fit(count: Int, in size: CGSize, spacing: CGFloat) -> (columns: Int, height: CGFloat) {
        guard count > 0, size.width > 0, size.height > 0 else { return (1, 1) }
        var best = (columns: 1, height: CGFloat(1), score: -CGFloat.infinity)
        for columns in 1...count {
            let rows = (count + columns - 1) / columns
            let width = (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let height = ((size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)).rounded(.down)
            let used = min(height, width)
            // Prefer tiles a little wider than tall.
            let score = min(width * 0.75, used)
            if score > best.score + 0.5 { best = (columns, max(used, 1), score) }
        }
        return (best.columns, best.height)
    }
}

/// Works like a slider: the lit part fills from the bottom to the brightness level, and
/// swiping up or down anywhere on the tile changes it. Tap to toggle, hold for color.
/// Switches to a single-row layout when tiles are short.
struct LightTile: View {
    @Environment(HomeStore.self) private var home
    var light: Light
    var showsRoom: Bool
    var height: CGFloat
    var onLongPress: () -> Void

    @State private var dragStart: Double?
    @State private var lastTick: Int?

    private var level: Double { light.isOn ? (light.brightness ?? 100) / 100 : 0 }
    /// Height of the lit part; a sliver stays visible at very low brightness.
    private var fillHeight: CGFloat { light.isOn ? height * max(level, 0.06) : 0 }
    private var tall: Bool { height >= 120 }

    var body: some View {
        ZStack {
            layout(.white)
            // Dark text over the lit part, so it reads right at the edge of the fill.
            layout(.black)
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: fillHeight)
                }
        }
        .background(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.92))
                .overlay(light.tint.opacity(0.22))
                .frame(height: fillHeight)
        }
        .clipShape(.rect(cornerRadius: Metrics.radius))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Metrics.radius))
        .opacity(light.isReachable ? 1 : 0.55)
        .contentShape(.rect(cornerRadius: Metrics.radius))
        .onTapGesture {
            Feedback.tap()
            withAnimation(.snappy) { home.toggle(light) }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            Feedback.press()
            onLongPress()
        }
        .simultaneousGesture(dimGesture)
        // Follow the finger exactly while dragging; animate other changes.
        .animation(dragStart == nil ? .snappy : nil, value: light)
    }

    private func layout(_ color: Color) -> some View {
        Group {
            if tall { tallLayout } else { rowLayout }
        }
        .foregroundStyle(color)
        .padding(tall ? 16 : 12)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                bulb(size: 40)
                Spacer()
                warning
            }
            Spacer(minLength: 4)
            Text(light.name)
                .font(.headline)
                .lineLimit(1)
            if showsRoom, height >= 140 {
                Text(light.roomName)
                    .font(.footnote)
                    .opacity(0.65)
                    .lineLimit(1)
            }
            Text(statusText)
                .font(.footnote.weight(.semibold))
                .opacity(0.8)
                .contentTransition(.numericText())
        }
    }

    private var rowLayout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                bulb(size: min(32, max(height - 28, 18)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(light.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if height >= 64 {
                        Text(statusText)
                            .font(.caption.weight(.semibold))
                            .opacity(0.8)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
                Spacer(minLength: 0)
                warning
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func bulb(size: CGFloat) -> some View {
        Image(systemName: light.isOn ? "lightbulb.fill" : "lightbulb")
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(light.isOn ? light.tint : .white.opacity(0.5))
            .shadow(color: light.isOn ? light.tint.opacity(0.8) : .clear, radius: 10)
            .frame(width: size, height: size)
            .background(Circle().fill(.white.opacity(light.isOn ? 0.9 : 0.1)))
    }

    @ViewBuilder private var warning: some View {
        if !light.isReachable {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.yellow)
        }
    }

    private var statusText: String {
        guard light.isReachable else { return "No Response" }
        guard light.isOn else { return "Off" }
        if let brightness = light.brightness { return "\(Int(brightness))%" }
        return "On"
    }

    /// Up brightens, down dims; the full tile height (at least 160 pt) spans 0–100%.
    private var dimGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard light.brightness != nil, light.isReachable,
                      dragStart != nil || abs(value.translation.height) > abs(value.translation.width) else { return }
                let start = dragStart ?? (light.isOn ? light.brightness ?? 100 : 0)
                dragStart = start
                let brightness = (start - Double(value.translation.height / max(height, 160)) * 100).clamped(to: 0...100)
                let tick = Int(brightness / 10)
                if tick != lastTick {
                    if lastTick != nil { Feedback.tick() }
                    lastTick = tick
                }
                home.setBrightness(brightness, for: light.id, commit: false)
            }
            .onEnded { _ in
                guard dragStart != nil else { return }
                dragStart = nil
                lastTick = nil
                let current = home.lights.first { $0.id == light.id }
                home.setBrightness(current?.isOn == true ? current?.brightness ?? 0 : 0, for: light.id, commit: true)
            }
    }
}

/// "Lights · 4 of 8 on", a color button for the whole room, and All On / All Off.
struct LightsHeader: View {
    @Environment(HomeStore.self) private var home
    @Environment(IdleMonitor.self) private var idle
    @Environment(AppSettings.self) private var settings
    @State private var confirmAllOff = false
    @State private var showRoomColor = false

    private func setAll(on: Bool) {
        Feedback.press()
        withAnimation(.snappy) { home.setAllVisible(on: on) }
    }

    var body: some View {
        SectionHeader(title: "Lights", symbol: "lightbulb.fill") {
            Text("\(home.lightsOnCount) of \(home.visibleLights.count) on")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            if home.visibleLights.contains(where: { $0.supportsColor || $0.colorTemperature != nil || $0.brightness != nil }) {
                Button {
                    Feedback.tap()
                    showRoomColor = true
                } label: {
                    Circle()
                        .fill(AngularGradient(colors: stride(from: 0.0, through: 360, by: 45).map {
                            Color(hue: $0 / 360, saturation: 0.85, brightness: 1)
                        }, center: .center))
                        .overlay(Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center,
                                                              startRadius: 0, endRadius: 11)))
                        .frame(width: 22, height: 22)
                        .frame(width: Metrics.headerHeight, height: Metrics.headerHeight)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Color for all lights")
            }
            Button {
                let turningOn = home.lightsOnCount == 0
                if !turningOn, settings.prefs.confirmAllOff, home.lightsOnCount >= 5 {
                    confirmAllOff = true
                } else {
                    setAll(on: turningOn)
                }
            } label: {
                Label(home.lightsOnCount == 0 ? "All On" : "All Off",
                      systemImage: home.lightsOnCount == 0 ? "lightbulb.max.fill" : "power")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: Metrics.headerHeight)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .sheet(isPresented: $showRoomColor) {
            RoomColorView()
                .presentationSizing(.page)
        }
        .onChange(of: idle.isSleeping) { _, sleeping in
            if sleeping { showRoomColor = false }
        }
        .alert("Turn off \(home.lightsOnCount) lights?", isPresented: $confirmAllOff) {
            Button("Turn Off") { setAll(on: false) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
