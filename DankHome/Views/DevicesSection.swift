//
//  DevicesSection.swift
//  DankHome
//

import SwiftUI

/// Locks, garage doors, shades, fans, outlets, switches and sensors. Only appears
/// when the home has any. Shows up to two rows; anything more goes behind "More".
struct DevicesRow: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings

    /// Width of the column the row sits in.
    var width: CGFloat
    /// Rows shown before the rest go behind "More". The iPhone, which scrolls, shows them all.
    var maxRows = 2
    @State private var showAll = false
    @State private var confirming: Device?
    @State private var detail: Device?

    private static let tileHeight: CGFloat = 52
    private static let minTileWidth: CGFloat = 150

    var body: some View {
        let devices = GridReorder.sorted(home.visibleDevices, by: settings.prefs.deviceOrder, key: \.key)
        if !devices.isEmpty {
            let columns = min(devices.count, max(1, Int((width + Metrics.gap) / (Self.minTileWidth + Metrics.gap))))
            let rows = min(maxRows, (devices.count + columns - 1) / columns)
            let overflow = devices.count > columns * rows
            let shown = overflow ? Array(devices.prefix(columns * rows - 1)) : devices
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Metrics.gap), count: columns),
                      spacing: Metrics.gap) {
                ForEach(shown) { tile($0) }
                if overflow { moreTile(count: devices.count - shown.count) }
            }
            .sheet(isPresented: $showAll) {
                AllDevicesView(onTap: tap, onHold: { detail = $0 })
                    .presentationSizing(.form)
            }
            .sheet(item: $detail) { DeviceDetailView(deviceID: $0.id) }
            .alert(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                   presenting: confirming) { device in
                Button(device.kind == .lock ? "Unlock" : "Open") { home.toggle(device) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var confirmTitle: String {
        guard let device = confirming else { return "" }
        return device.kind == .lock ? "Unlock \(device.name)?" : "Open \(device.name)?"
    }

    private func tap(_ device: Device) {
        guard device.isControllable, device.isReachable else { return }
        Feedback.tap()
        if device.needsConfirmation {
            confirming = device
        } else {
            withAnimation(.snappy) { home.toggle(device) }
        }
    }

    private func tile(_ device: Device) -> some View {
        DeviceTile(device: device, height: Self.tileHeight)
            .onTapGesture { tap(device) }
            .onLongPressGesture(minimumDuration: 0.4) {
                guard device.kind == .shade || device.kind == .fan else { return }
                Feedback.press()
                detail = device
            }
    }

    private func moreTile(count: Int) -> some View {
        Button {
            showAll = true
        } label: {
            Label("\(count) More", systemImage: "ellipsis.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Self.tileHeight)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Metrics.radius))
    }
}

struct DeviceTile: View {
    var device: Device
    var height: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(device.isHighlighted ? .white : device.tint)
                .symbolEffect(.rotate, isActive: device.kind == .fan && device.active)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .background(Circle().fill(device.isHighlighted ? device.tint : device.tint.opacity(0.18)))
            VStack(alignment: .leading, spacing: 0) {
                Text(device.name)
                    .font(.subheadline.weight(.semibold))
                Text(device.status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(device.hasProblem ? .red : .white.opacity(0.65))
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Metrics.radius))
        .opacity(device.isReachable ? 1 : 0.55)
        .contentShape(.rect(cornerRadius: Metrics.radius))
        .animation(.snappy, value: device)
    }
}

/// Every device, for when they don't all fit on the dashboard.
struct AllDevicesView: View {
    @Environment(HomeStore.self) private var home
    @Environment(\.dismiss) private var dismiss
    var onTap: (Device) -> Void
    var onHold: (Device) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Metrics.gap)], spacing: Metrics.gap) {
                    ForEach(home.visibleDevices) { device in
                        DeviceTile(device: device, height: 56)
                            .onTapGesture { onTap(device) }
                            .onLongPressGesture(minimumDuration: 0.4) {
                                guard device.kind == .shade || device.kind == .fan else { return }
                                dismiss()
                                onHold(device)
                            }
                    }
                }
                .padding(Metrics.margin)
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Big slider for a shade's position or a fan's speed.
struct DeviceDetailView: View {
    @Environment(HomeStore.self) private var home
    @Environment(\.dismiss) private var dismiss
    var deviceID: UUID
    @State private var dragStart: Double?

    var body: some View {
        if let device = home.devices.first(where: { $0.id == deviceID }) {
            let level = device.level ?? (device.active ? 100 : 0)
            let height: CGFloat = 340
            VStack(spacing: 28) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name).font(.largeTitle.bold())
                        Text(device.roomName).font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(.glass)
                }
                Spacer()
                ZStack(alignment: .bottom) {
                    Rectangle().fill(.white.opacity(0.12))
                    Rectangle().fill(device.tint.gradient).frame(height: height * level / 100)
                    Image(systemName: device.symbol)
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.bottom, 28)
                }
                .frame(width: 150, height: height)
                .clipShape(.rect(cornerRadius: 44))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let start = dragStart ?? level
                            dragStart = start
                            home.setLevel(start - Double(value.translation.height / height) * 100, for: device.id)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                Text(device.status)
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .contentTransition(.numericText())
                Spacer()
            }
            .padding(40)
            .animation(.snappy, value: device)
        }
    }
}
