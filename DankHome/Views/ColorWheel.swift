//
//  ColorWheel.swift
//  DankHome
//

import SwiftUI

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
