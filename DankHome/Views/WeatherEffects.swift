//
//  WeatherEffects.swift
//  DankHome
//
//  Subtle animated weather behind the dashboard: rain on the glass, falling snow,
//  drifting clouds and the odd lightning flash. Drawn with Canvas at 30 fps.
//

import SwiftUI

enum WeatherEffect: Equatable {
    case none, clouds, fog, rain(heavy: Bool), snow, storm

    init(code: Int) {
        switch code {
        case 2, 3: self = .clouds
        case 45, 48: self = .fog
        case 51...57, 61, 80: self = .rain(heavy: false)
        case 63...67, 81, 82: self = .rain(heavy: true)
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .storm
        default: self = .none
        }
    }

    var hasClouds: Bool {
        switch self {
        case .clouds, .fog, .rain, .snow, .storm: true
        case .none: false
        }
    }
}

struct WeatherEffectsView: View {
    var effect: WeatherEffect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if effect != .none, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { canvas, size in
                    if effect.hasClouds { drawClouds(&canvas, size: size, t: t) }
                    switch effect {
                    case .rain(let heavy): drawRain(&canvas, size: size, t: t, count: heavy ? 140 : 80)
                    case .storm:
                        drawRain(&canvas, size: size, t: t, count: 150)
                        drawLightning(&canvas, size: size, t: t)
                    case .snow: drawSnow(&canvas, size: size, t: t)
                    default: break
                    }
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Stable pseudo-random 0…1 for particle `i`, variant `k`.
    private func random(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
        return x - floor(x)
    }

    private func drawClouds(_ canvas: inout GraphicsContext, size: CGSize, t: Double) {
        var layer = canvas
        layer.addFilter(.blur(radius: 60))
        let opacity = effect == .fog ? 0.16 : 0.09
        for i in 0..<6 {
            let width = size.width * (0.45 + random(i, 1) * 0.4)
            let height = width * 0.35
            let speed = 6 + random(i, 2) * 10
            let span = size.width + width
            let x = (random(i, 3) * span + t * speed).truncatingRemainder(dividingBy: span) - width
            let y = size.height * (effect == .fog ? random(i, 4) : random(i, 4) * 0.55)
            layer.fill(Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height)),
                       with: .color(.white.opacity(opacity)))
        }
    }

    private func drawRain(_ canvas: inout GraphicsContext, size: CGSize, t: Double, count: Int) {
        let slant = 0.18
        for i in 0..<count {
            let speed = 700 + random(i, 1) * 500
            let length = 14 + random(i, 2) * 22
            let span = size.height + length
            let y = (random(i, 3) * span + t * speed).truncatingRemainder(dividingBy: span) - length
            let x = random(i, 4) * (size.width + 100) - 50 + y * slant
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + length * slant, y: y + length))
            canvas.stroke(path, with: .color(.white.opacity(0.08 + random(i, 5) * 0.1)), lineWidth: 1.2)
        }
    }

    private func drawSnow(_ canvas: inout GraphicsContext, size: CGSize, t: Double) {
        for i in 0..<90 {
            let speed = 25 + random(i, 1) * 45
            let radius = 1.5 + random(i, 2) * 3
            let span = size.height + 10
            let y = (random(i, 3) * span + t * speed).truncatingRemainder(dividingBy: span) - 5
            let sway = sin(t * (0.5 + random(i, 4)) + Double(i)) * 18
            let x = random(i, 5) * size.width + sway
            canvas.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                        with: .color(.white.opacity(0.25 + random(i, 6) * 0.35)))
        }
    }

    /// A quick double flash roughly every 12 seconds.
    private func drawLightning(_ canvas: inout GraphicsContext, size: CGSize, t: Double) {
        let phase = t.truncatingRemainder(dividingBy: 12)
        let flash = phase < 0.08 ? 0.22 : (phase > 0.16 && phase < 0.22) ? 0.12 : 0
        guard flash > 0 else { return }
        canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flash)))
    }
}
