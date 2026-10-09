//
//  LightsSection.swift
//  DankHome
//

import SwiftUI

/// A row of chips that never scrolls: it tightens its padding, then drops to icons,
/// then collapses into a menu — whichever is the first that fits.
struct ChipRow: View {
    struct Chip: Identifiable {
        var id: String
        var title: String
        var symbol: String?
    }

    var chips: [Chip]
    /// Stretch chips to share the full width.
    var fill = false
    var selectedID: String?
    /// Label for the collapsed menu.
    var menuTitle: String
    var menuSymbol: String
    var action: (Chip) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(padding: 16, showsTitle: true)
            row(padding: 10, showsTitle: true)
            if chips.allSatisfy({ $0.symbol != nil }) {
                row(padding: 10, showsTitle: false)
            }
            menu
        }
    }

    private func row(padding: CGFloat, showsTitle: Bool) -> some View {
        GlassEffectContainer(spacing: Metrics.chipGap) {
            HStack(spacing: Metrics.chipGap) {
                ForEach(chips) { chip in
                    let selected = chip.id == selectedID
                    Button {
                        Feedback.tap()
                        withAnimation(.snappy) { action(chip) }
                    } label: {
                        Group {
                            if showsTitle {
                                if let symbol = chip.symbol {
                                    Label(chip.title, systemImage: symbol)
                                } else {
                                    Text(chip.title)
                                }
                            } else {
                                Image(systemName: chip.symbol ?? "circle")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? .black : .white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, padding)
                        .frame(maxWidth: fill ? .infinity : nil)
                        .frame(height: Metrics.headerHeight)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(selected ? .regular.tint(.white).interactive() : .regular.interactive(), in: .capsule)
                }
            }
        }
    }

    private var menu: some View {
        Menu {
            ForEach(chips) { chip in
                Button {
                    action(chip)
                } label: {
                    if let symbol = chip.symbol {
                        Label(chip.title, systemImage: symbol)
                    } else {
                        Text(chip.title)
                    }
                }
            }
        } label: {
            Label(menuTitle, systemImage: menuSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(maxWidth: fill ? .infinity : nil)
                .frame(height: Metrics.headerHeight)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

struct RoomPicker: View {
    @Environment(HomeStore.self) private var home
    private static let allID = "__all__"

    var body: some View {
        ChipRow(
            chips: [.init(id: Self.allID, title: "All Rooms")] + home.roomNames.map { .init(id: $0, title: $0) },
            selectedID: home.selectedRoom ?? Self.allID,
            menuTitle: home.selectedRoom ?? "All Rooms",
            menuSymbol: "square.grid.2x2"
        ) { chip in
            home.selectedRoom = chip.id == Self.allID ? nil : chip.id
        }
    }
}

struct LightsGrid: View {
    @Environment(HomeStore.self) private var home
    @Environment(IdleMonitor.self) private var idle
    @Environment(AppSettings.self) private var settings
    @Environment(UndoCenter.self) private var undo
    @State private var detailLight: Light?
    @State private var confirmAllOff = false

    /// The saved arrangement (older versions pinned lights instead).
    private var savedOrder: [String] {
        settings.prefs.lightOrder.isEmpty ? settings.prefs.pinnedLights : settings.prefs.lightOrder
    }

    private var orderedLights: [Light] {
        GridReorder.sorted(home.visibleLights, by: savedOrder, key: \.key)
    }

    private func setAll(on: Bool) {
        Feedback.press()
        undo.perform(on ? "All lights on" : "All lights off", home: home) {
            withAnimation(.snappy) { home.setAllVisible(on: on) }
        }
    }

    private let spacing = Metrics.gap

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.gap) {
            SectionHeader(title: "Lights", symbol: "lightbulb.fill") {
                Text("\(home.lightsOnCount) of \(home.visibleLights.count) on")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
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
        .alert("Turn off \(home.lightsOnCount) lights?", isPresented: $confirmAllOff) {
            Button("Turn Off") { setAll(on: false) }
            Button("Cancel", role: .cancel) {}
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

struct ScenesRow: View {
    @Environment(HomeStore.self) private var home
    @Environment(UndoCenter.self) private var undo
    @Environment(MusicStore.self) private var music
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let buttons = settings.sceneButtons(home: home)
        if !buttons.isEmpty {
            ChipRow(
                chips: buttons.map { .init(id: $0.id.uuidString, title: $0.name.isEmpty ? "New Button" : $0.name, symbol: $0.symbol) },
                fill: true,
                menuTitle: "Scenes",
                menuSymbol: "sparkles"
            ) { chip in
                if let button = buttons.first(where: { $0.id.uuidString == chip.id }) {
                    undo.perform(button.name, home: home) {
                        SceneRunner(home: home, music: music, settings: settings).run(button)
                    }
                }
            }
        }
    }
}

/// Hue around the edge, saturation toward the center. Drag anywhere to pick any color.
struct ColorWheel: View {
    var hue: Double           // 0…360
    var saturation: Double    // 0…100
    var showsThumb: Bool
    var onChange: (Double, Double) -> Void

    @State private var dragging: (hue: Double, saturation: Double)?

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let shown = dragging ?? (hue, saturation)
            let angle = shown.hue * .pi / 180
            let distance = radius * shown.saturation / 100
            let thumb = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)

            ZStack {
                Circle()
                    .fill(AngularGradient(colors: stride(from: 0.0, through: 360, by: 30).map {
                        Color(hue: $0 / 360, saturation: 1, brightness: 1)
                    }, center: .center))
                Circle()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: radius))
                if showsThumb || dragging != nil {
                    Circle()
                        .fill(Color(hue: shown.hue / 360, saturation: shown.saturation / 100, brightness: 1))
                        .frame(width: dragging == nil ? 34 : 46, height: dragging == nil ? 34 : 46)
                        .overlay(Circle().stroke(.white, lineWidth: 4))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .position(thumb)
                        .animation(.spring(response: 0.25), value: dragging == nil)
                }
            }
            .frame(width: size, height: size)
            .position(center)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        var degrees = atan2(dy, dx) * 180 / .pi
                        if degrees < 0 { degrees += 360 }
                        let sat = (hypot(dx, dy) / radius * 100).clamped(to: 0...100)
                        let picked = (hue: Double(degrees.rounded()), saturation: Double(sat.rounded()))
                        if dragging == nil { Feedback.tap() }
                        dragging = picked
                        onChange(picked.0, picked.1)
                    }
                    .onEnded { _ in dragging = nil }
            )
        }
        .accessibilityLabel("Color wheel")
    }
}
