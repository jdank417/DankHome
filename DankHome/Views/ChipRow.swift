//
//  ChipRow.swift
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

struct ScenesRow: View {
    @Environment(HomeStore.self) private var home
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
                    SceneRunner(home: home, music: music, settings: settings).run(button)
                }
            }
        }
    }
}
