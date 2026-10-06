// Renders the app icon: five glass level bars, the dictation pill's meter, on a deep blue squircle,
// with a text cursor beside them for "speech into text".
// Usage: swift scripts/make-app-icon.swift Resources/AppIcon.icns
//
// Draws every size of a macOS .iconset on Apple's icon grid (an 824 pt body on a 1024 pt canvas)
// and packs them with iconutil.
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Draws the icon on a 1024 x 1024 canvas; the caller scales the context.
func drawIcon() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // A soft shadow under the body, as on the system icons.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Deep blue to indigo, lit from the top.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.33, green: 0.62, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.33, blue: 0.92, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.12, blue: 0.55, alpha: 1),
    ])!.draw(in: body, angle: -90)
    // A broad sheen across the top half, the way glass catches light.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // A thin light rim.
    NSColor.white.withAlphaComponent(0.35).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: 182, yRadius: 182)
    rim.lineWidth = 6
    rim.stroke()

    // Five glass bars, weighted like the HUD meter, then a cursor.
    let weights: [CGFloat] = [0.42, 0.7, 1, 0.7, 0.42]
    let barWidth: CGFloat = 70, gap: CGFloat = 38, tallest: CGFloat = 470
    let cursorGap: CGFloat = 64, cursorWidth: CGFloat = 26
    let total = CGFloat(weights.count) * barWidth + CGFloat(weights.count - 1) * gap + cursorGap + cursorWidth
    var x = 512 - total / 2
    func glassCapsule(_ rect: NSRect, alpha: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor(srgbRed: 0.05, green: 0.08, blue: 0.35, alpha: 0.45)
        glow.shadowBlurRadius = 18
        glow.shadowOffset = NSSize(width: 0, height: -8)
        glow.set()
        NSColor.white.withAlphaComponent(alpha).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: [NSColor.white.withAlphaComponent(0), NSColor(srgbRed: 0.75, green: 0.85, blue: 1, alpha: 0.5)])!
            .draw(in: rect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }
    for weight in weights {
        let height = tallest * weight
        glassCapsule(NSRect(x: x, y: 512 - height / 2, width: barWidth, height: height), alpha: 0.95)
        x += barWidth + gap
    }
    x += cursorGap - gap
    glassCapsule(NSRect(x: x, y: 512 - 290 / 2, width: cursorWidth, height: 290), alpha: 0.75)
}

let sizes: [(name: String, pixels: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
    ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
]
for (name, pixels) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: iconset.appendingPathComponent("icon_\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try! iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
