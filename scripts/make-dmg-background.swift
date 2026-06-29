#!/usr/bin/env swift
import AppKit

// Renders the Sumbee DMG window background: warm beeswax gradient, a faint honeycomb
// lattice, and an amber drag arrow pointing from the app to the Applications folder.
// Headless-safe (explicit bitmap context, scaled for @2x). The Finder lays the real
// app icon over the left and the Applications shortcut over the right at runtime.
//
// Usage: swift scripts/make-dmg-background.swift <out.png> <scale>

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "dmg-bg.png"
let scale = args.count > 2 ? (Double(args[2]) ?? 1) : 1
let W: CGFloat = 600, H: CGFloat = 400          // window content size in points
let pxW = Int(W * CGFloat(scale)), pxH = Int(H * CGFloat(scale))

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))   // draw in logical 600x400

let full = NSRect(x: 0, y: 0, width: W, height: H)

// Beeswax gradient (cream at top, soft honey at the bottom).
NSGradient(colors: [
    NSColor(srgbRed: 0.992, green: 0.961, blue: 0.902, alpha: 1),
    NSColor(srgbRed: 0.964, green: 0.882, blue: 0.700, alpha: 1),
])?.draw(in: full, angle: -90)

// Faint honeycomb lattice (pointy-top hex grid).
func hexPath(cx: CGFloat, cy: CGFloat, r: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    for i in 0..<6 {
        let a = CGFloat.pi / 180 * (60 * CGFloat(i) - 30)
        let pt = NSPoint(x: cx + r * cos(a), y: cy + r * sin(a))
        if i == 0 { p.move(to: pt) } else { p.line(to: pt) }
    }
    p.close()
    return p
}
let r: CGFloat = 34, hdx = r * CGFloat(3).squareRoot(), hdy = r * 1.5
NSColor(srgbRed: 0.80, green: 0.55, blue: 0.18, alpha: 0.10).setStroke()
var rowY = -r, row = 0
while rowY < H + r {
    var x = -r + (row % 2 == 0 ? 0 : hdx / 2)
    while x < W + r {
        let hp = hexPath(cx: x, cy: rowY, r: r)
        hp.lineWidth = 1.5
        hp.stroke()
        x += hdx
    }
    rowY += hdy; row += 1
}

// Drag arrow (amber), centered vertically between the two icon slots.
let cy = H / 2
let accent = NSColor(srgbRed: 1.0, green: 0.478, blue: 0.102, alpha: 0.92)
accent.setStroke()
let shaft = NSBezierPath()
shaft.lineWidth = 9; shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 246, y: cy))
shaft.line(to: NSPoint(x: 352, y: cy))
shaft.stroke()
let head = NSBezierPath()
head.lineWidth = 9; head.lineCapStyle = .round; head.lineJoinStyle = .round
head.move(to: NSPoint(x: 338, y: cy + 15))
head.line(to: NSPoint(x: 360, y: cy))
head.line(to: NSPoint(x: 338, y: cy - 15))
head.stroke()

// Rounded type, to echo the app's SF Rounded display.
func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: d, size: size) ?? base }
    return base
}
let center = NSMutableParagraphStyle(); center.alignment = .center

NSAttributedString(string: "Sumbee", attributes: [
    .font: rounded(26, .bold),
    .foregroundColor: NSColor(srgbRed: 0.84, green: 0.30, blue: 0.02, alpha: 1.0),
    .paragraphStyle: center,
]).draw(in: NSRect(x: 0, y: H - 62, width: W, height: 34))

NSAttributedString(string: "Drag Sumbee to your Applications folder", attributes: [
    .font: rounded(15, .medium),
    .foregroundColor: NSColor(srgbRed: 0.42, green: 0.30, blue: 0.12, alpha: 1.0),
    .paragraphStyle: center,
]).draw(in: NSRect(x: 0, y: 54, width: W, height: 22))

NSGraphicsContext.restoreGraphicsState()
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(pxW)x\(pxH))")
