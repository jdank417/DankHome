// Renders the DankHome app icon: an anchor whose ring sits under a roof,
// so the anchor reads as a house. Usage: swift icon.swift <output-dir>
import AppKit
import CoreGraphics

let size = 1024
let out = CommandLine.arguments[1]

enum Variant: String { case light = "AppIcon", dark = "AppIcon-Dark", tinted = "AppIcon-Tinted" }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ variant: Variant) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Flip so y grows downward, like a design canvas.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)

    // Background
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    switch variant {
    case .light:
        let gradient = CGGradient(colorsSpace: space, colors: [color(0x0B2A4A), color(0x0E5A7E), color(0x1BA3B8)] as CFArray,
                                  locations: [0, 0.6, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])
        // Soft glow behind the mark
        let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray,
                              locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 470), endRadius: 520, options: [])
    case .dark:
        ctx.setFillColor(color(0x0A0D14))
        ctx.fill(full)
    case .tinted:
        ctx.setFillColor(color(0x000000))
        ctx.fill(full)
    }

    // The mark, drawn as round-capped strokes.
    let stroke: CGFloat = 58
    let path = CGMutablePath()
    // Roof
    path.move(to: CGPoint(x: 236, y: 452))
    path.addLine(to: CGPoint(x: 512, y: 222))
    path.addLine(to: CGPoint(x: 788, y: 452))
    // Ring (the attic window)
    path.addEllipse(in: CGRect(x: 512 - 46, y: 368 - 46, width: 92, height: 92))
    // Shank
    path.move(to: CGPoint(x: 512, y: 414))
    path.addLine(to: CGPoint(x: 512, y: 812))
    // Stock
    path.move(to: CGPoint(x: 404, y: 512))
    path.addLine(to: CGPoint(x: 620, y: 512))
    // Arms: a U that sweeps up to where the house walls would be
    path.move(to: CGPoint(x: 268, y: 610))
    path.addQuadCurve(to: CGPoint(x: 512, y: 812), control: CGPoint(x: 300, y: 800))
    path.addQuadCurve(to: CGPoint(x: 756, y: 610), control: CGPoint(x: 724, y: 800))

    // Flukes: arrowheads at the tips of the arms
    let flukes = CGMutablePath()
    flukes.move(to: CGPoint(x: 268, y: 552))
    flukes.addLine(to: CGPoint(x: 226, y: 650))
    flukes.addLine(to: CGPoint(x: 330, y: 640))
    flukes.closeSubpath()
    flukes.move(to: CGPoint(x: 756, y: 552))
    flukes.addLine(to: CGPoint(x: 798, y: 650))
    flukes.addLine(to: CGPoint(x: 694, y: 640))
    flukes.closeSubpath()

    let markColor: CGColor
    switch variant {
    case .light: markColor = color(0xFFFFFF)
    case .dark: markColor = color(0x5CD6E6)
    case .tinted: markColor = color(0xFFFFFF)
    }

    // Subtle drop shadow for depth on the colored icon
    if variant == .light {
        ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: color(0x000000, 0.28))
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setStrokeColor(markColor)
    ctx.setFillColor(markColor)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(path)
    ctx.strokePath()
    ctx.addPath(flukes)
    ctx.setLineWidth(18)
    ctx.drawPath(using: .fillStroke)
    ctx.endTransparencyLayer()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/\(variant.rawValue).png"))
}

for variant in [Variant.light, .dark, .tinted] { render(variant) }
print("done")
