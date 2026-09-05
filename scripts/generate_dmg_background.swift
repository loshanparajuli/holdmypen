// Renders the background image for the installer DMG: two icon-drop
// positions (the app, and /Applications) connected by an arrow, so the
// window makes "drag me over there" obvious at a glance.
//
// Usage: swift generate_dmg_background.swift <output.png>

import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    print("usage: swift generate_dmg_background.swift <output.png>")
    exit(1)
}
let outputPath = args[1]

let width: CGFloat = 660
let height: CGFloat = 400
let iconSize: CGFloat = 128
let iconY: CGFloat = height - 210
let appIconX: CGFloat = 150
let applicationsIconX: CGFloat = 510

// Render into an explicit 1x-pixel bitmap context rather than via
// NSImage.lockFocus(), which follows the screen's backing scale factor
// (2x on Retina) and would silently double the output's pixel dimensions —
// throwing off the icon positions Finder is told to use against this image.
guard let bitmapRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width),
    pixelsHigh: Int(height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    print("failed to create bitmap")
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)

// Plain white background — no caption, just the arrow between the icons.
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// Arrow between the two icon slots.
let arrowY = iconY + iconSize / 2
let arrowStartX = appIconX + iconSize / 2 + 24
let arrowEndX = applicationsIconX - iconSize / 2 - 24

let shaftPath = NSBezierPath()
shaftPath.lineWidth = 6
shaftPath.lineCapStyle = .round
NSColor.black.withAlphaComponent(0.75).setStroke()
shaftPath.move(to: NSPoint(x: arrowStartX, y: arrowY))
shaftPath.line(to: NSPoint(x: arrowEndX - 18, y: arrowY))
shaftPath.stroke()

let headPath = NSBezierPath()
headPath.move(to: NSPoint(x: arrowEndX - 28, y: arrowY + 20))
headPath.line(to: NSPoint(x: arrowEndX, y: arrowY))
headPath.line(to: NSPoint(x: arrowEndX - 28, y: arrowY - 20))
NSColor.black.withAlphaComponent(0.75).setFill()
headPath.fill()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    print("failed to render PNG")
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("wrote \(outputPath)")
} catch {
    print("failed to write file: \(error)")
    exit(1)
}
