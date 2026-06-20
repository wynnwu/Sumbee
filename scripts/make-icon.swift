#!/usr/bin/env swift
import AppKit

// Generates an .iconset of an orange-gradient "S" monogram using an explicit bitmap
// context (works headless, without a running NSApplication). Run via scripts/make-icon.sh.

func makePNG(_ px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let size = CGFloat(px)
    let full = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.045
    let rect = full.insetBy(dx: inset, dy: inset)
    let corner = rect.width * 0.2237

    let clip = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    clip.addClip()

    if let gradient = NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.64, blue: 0.22, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.478, blue: 0.102, alpha: 1),
        NSColor(srgbRed: 0.84, green: 0.30, blue: 0.02, alpha: 1),
    ]) {
        gradient.draw(in: rect, angle: -90)
    }
    if let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.20), .clear]) {
        sheen.draw(in: rect, angle: -90)
    }

    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let font = NSFont.systemFont(ofSize: size * 0.60, weight: .heavy)
    let glyph = NSAttributedString(string: "S", attributes: [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: para,
    ])
    let gs = glyph.size()
    glyph.draw(at: NSPoint(x: (size - gs.width) / 2, y: (size - gs.height) / 2 - size * 0.015))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let iconset = "scripts/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let specs: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (base, scale) in specs {
    let px = base * scale
    guard let data = makePNG(px) else {
        FileHandle.standardError.write("icon failed at \(px)px\n".data(using: .utf8)!)
        exit(1)
    }
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
}
print("Wrote \(iconset)")
