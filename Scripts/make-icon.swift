#!/usr/bin/env swift
// Turns a square source image into Icon/Sleight.icns.
//
//     swift Scripts/make-icon.swift [zoom]
//
// The source is expected to be full-bleed, with its subject well inside the
// middle - no rounded corners and no transparency. Both are added here, because
// getting them right matters more than a generator can be trusted to:
//
//   - macOS icons are not rounded rectangles. The corners are a continuous
//     curve, and a plain corner radius reads as subtly wrong next to every
//     other icon in the Dock.
//   - The artwork occupies 824 of a 1024 canvas, centred, with the rest left
//     transparent for the system's shadow. Filling the canvas edge to edge
//     makes an icon that looks bigger and flatter than its neighbours.
import AppKit

let canvas: CGFloat = 1024
let body: CGFloat = 824  // Apple's grid for macOS app icons
let zoom = CGFloat(CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 1.0)

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = root.appendingPathComponent("Icon/source.jpg")
let iconset = root.appendingPathComponent("Icon/Sleight.iconset")

guard let source = NSImage(contentsOf: sourceURL) else {
    print("no source image at \(sourceURL.path)")
    exit(1)
}

/// A superellipse, which is what Apple's icon corners actually are. Exponent 5
/// matches the shape closely enough that it sits correctly beside system icons.
func squircle(in rect: CGRect, exponent: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let (a, b) = (rect.width / 2, rect.height / 2)
    let (cx, cy) = (rect.midX, rect.midY)
    let steps = 720

    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let (c, s) = (cos(t), sin(t))
        // Signed |cos|^(2/n) keeps the curve continuous through each quadrant.
        let x = cx + a * copysign(pow(abs(c), 2 / exponent), c)
        let y = cy + b * copysign(pow(abs(s), 2 / exponent), s)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.line(to: CGPoint(x: x, y: y))
    }
    path.close()
    return path
}

/// Draws the source into the icon body at one size.
func render(size: CGFloat) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high

    let scale = size / canvas
    let side = body * scale
    let inset = (size - side) / 2
    let bodyRect = CGRect(x: inset, y: inset, width: side, height: side)

    squircle(in: bodyRect).addClip()
    // Zoom crops rather than shrinks, since the background is full-bleed.
    let drawn = bodyRect.insetBy(dx: -side * (zoom - 1) / 2, dy: -side * (zoom - 1) / 2)
    source.draw(in: drawn, from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The exact set iconutil expects; a missing size makes it refuse the folder.
let wanted: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in wanted {
    guard let data = render(size: size) else {
        print("could not render \(name)")
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

print("wrote \(wanted.count) sizes to \(iconset.lastPathComponent) (zoom \(zoom))")
