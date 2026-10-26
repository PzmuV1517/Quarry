// Renders the app icon (a cut gem on the Ferriteworks tile) into Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / canvas
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)

    // macOS icon grid: 824pt rounded square centered on a 1024pt canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Ferriteworks monochrome: graphite fading to black, with a faint dot grid.
    NSGradient(colors: [
        NSColor(srgbRed: 0.17, green: 0.17, blue: 0.17, alpha: 1),
        NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1),
    ])!.draw(in: tilePath, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSColor.white.withAlphaComponent(0.10).setFill()
    for x in stride(from: tile.minX + 16, to: tile.maxX, by: 32) {
        for y in stride(from: tile.minY + 16, to: tile.maxY, by: 32) {
            NSBezierPath(ovalIn: NSRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.12).setStroke()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
    rim.lineWidth = 4
    rim.stroke()

    // A cut gem: three crown facets over three pavilion facets, lit from the top left.
    func facet(_ points: [(CGFloat, CGFloat)], _ top: CGFloat, _ bottom: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: points[0].0, y: points[0].1))
        points.dropFirst().forEach { path.line(to: NSPoint(x: $0.0, y: $0.1)) }
        path.close()
        NSGradient(starting: NSColor(white: top, alpha: 1), ending: NSColor(white: bottom, alpha: 1))!.draw(in: path, angle: -90)
        NSColor.black.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 5
        path.lineJoinStyle = .round
        path.stroke()
    }
    let table = (left: (CGFloat(382), CGFloat(712)), right: (CGFloat(642), CGFloat(712)))
    let girdle = (left: (CGFloat(226), CGFloat(572)), innerLeft: (CGFloat(447), CGFloat(572)),
                  innerRight: (CGFloat(577), CGFloat(572)), right: (CGFloat(798), CGFloat(572)))
    let tip = (CGFloat(512), CGFloat(214))
    facet([girdle.left, table.left, girdle.innerLeft], 0.80, 0.66)
    facet([table.left, table.right, girdle.innerRight, girdle.innerLeft], 0.98, 0.84)
    facet([table.right, girdle.right, girdle.innerRight], 0.60, 0.48)
    facet([girdle.left, girdle.innerLeft, tip], 0.50, 0.30)
    facet([girdle.innerLeft, girdle.innerRight, tip], 0.78, 0.46)
    facet([girdle.innerRight, girdle.right, tip], 0.34, 0.18)

    // Subtle top highlight for depth.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.08), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(size: CGFloat(points)).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(size: CGFloat(points * 2)).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try render(size: 1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
