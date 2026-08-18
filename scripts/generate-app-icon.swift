import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes = [16, 32, 128, 256, 512]
let background = NSColor(calibratedRed: 0.025, green: 0.16, blue: 0.17, alpha: 1)
let foreground = NSColor(calibratedRed: 0.88, green: 0.95, blue: 0.93, alpha: 1)
let sparkle = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.16, alpha: 1)

func writePNG(size: Int, scale: Int, name: String) throws {
    let pixels = size * scale
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "HermesUsageMonitorIcon", code: 2)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    background.setFill()
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(pixels) * 0.22, yRadius: CGFloat(pixels) * 0.22).fill()

    let inset = CGFloat(pixels) * 0.14
    let ringRect = rect.insetBy(dx: inset, dy: inset)
    foreground.setStroke()
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = CGFloat(pixels) * 0.045
    ring.stroke()

    let font = NSFont.systemFont(ofSize: CGFloat(pixels) * 0.42, weight: .bold)
    let text = NSString(string: "H")
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
    let textSize = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (CGFloat(pixels) - textSize.width) / 2, y: (CGFloat(pixels) - textSize.height) / 2 - CGFloat(pixels) * 0.015), withAttributes: attributes)

    sparkle.setStroke()
    let center = NSPoint(x: CGFloat(pixels) * 0.78, y: CGFloat(pixels) * 0.82)
    let radius = CGFloat(pixels) * 0.075
    let rays = NSBezierPath()
    rays.move(to: NSPoint(x: center.x, y: center.y - radius * 2.2))
    rays.line(to: NSPoint(x: center.x, y: center.y + radius * 2.2))
    rays.move(to: NSPoint(x: center.x - radius * 2.2, y: center.y))
    rays.line(to: NSPoint(x: center.x + radius * 2.2, y: center.y))
    rays.move(to: NSPoint(x: center.x - radius * 1.5, y: center.y - radius * 1.5))
    rays.line(to: NSPoint(x: center.x + radius * 1.5, y: center.y + radius * 1.5))
    rays.move(to: NSPoint(x: center.x - radius * 1.5, y: center.y + radius * 1.5))
    rays.line(to: NSPoint(x: center.x + radius * 1.5, y: center.y - radius * 1.5))
    rays.lineWidth = max(1, CGFloat(pixels) * 0.025)
    rays.stroke()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "HermesUsageMonitorIcon", code: 1)
    }
    try data.write(to: outputDirectory.appendingPathComponent(name))
}

for size in sizes {
    try writePNG(size: size, scale: 1, name: "icon_\(size)x\(size).png")
    try writePNG(size: size, scale: 2, name: "icon_\(size)x\(size)@2x.png")
}
