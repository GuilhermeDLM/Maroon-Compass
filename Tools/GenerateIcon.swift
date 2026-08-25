import AppKit

// Legacy deterministic fallback. The shipping icon is the curated master artwork in
// Assets.xcassets/AppIcon.appiconset; running this tool intentionally replaces it.

guard CommandLine.arguments.count > 1 else {
    fputs("Output path required\n", stderr)
    exit(1)
}

let variant = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "light"
let size = NSSize(width: 1024, height: 1024)
guard let bitmapContext = CGContext(
    data: nil,
    width: 1024,
    height: 1024,
    bitsPerComponent: 8,
    bytesPerRow: 1024 * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fputs("Unable to create icon canvas\n", stderr)
    exit(1)
}
let graphicsContext = NSGraphicsContext(cgContext: bitmapContext, flipped: false)

let colors: (top: NSColor, bottom: NSColor, highlight: NSColor) = switch variant {
case "dark": (
    NSColor(calibratedRed: 0.04, green: 0.22, blue: 0.49, alpha: 1),
    NSColor(calibratedRed: 0.01, green: 0.045, blue: 0.11, alpha: 1),
    NSColor(calibratedRed: 0.42, green: 0.78, blue: 1.00, alpha: 1)
)
case "tinted": (
    NSColor(calibratedWhite: 0.32, alpha: 1),
    NSColor(calibratedWhite: 0.06, alpha: 1),
    NSColor(calibratedWhite: 0.92, alpha: 1)
)
default: (
    NSColor(calibratedRed: 0.05, green: 0.38, blue: 0.82, alpha: 1),
    NSColor(calibratedRed: 0.015, green: 0.11, blue: 0.28, alpha: 1),
    NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.25, alpha: 1)
)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

let canvas = NSRect(origin: .zero, size: size)
colors.bottom.setFill()
NSBezierPath(rect: canvas).fill()
let gradient = NSGradient(colors: [colors.top, colors.bottom])
gradient?.draw(in: canvas, angle: -55)

let glow = NSBezierPath(ovalIn: NSRect(x: 610, y: 610, width: 500, height: 500))
colors.highlight.withAlphaComponent(0.20).setFill()
glow.fill()

let lowerGlow = NSBezierPath(ovalIn: NSRect(x: -170, y: -130, width: 510, height: 510))
NSColor(calibratedWhite: 1, alpha: 0.09).setFill()
lowerGlow.fill()

let cardRect = NSRect(x: 177, y: 172, width: 670, height: 680)
let card = NSBezierPath(roundedRect: cardRect, xRadius: 132, yRadius: 132)
NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
card.fill()
NSColor(calibratedWhite: 1, alpha: 0.20).setStroke()
card.lineWidth = 5
card.stroke()

for column in 1...3 {
    let x = 310 + CGFloat(column - 1) * 202
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x, y: 254))
    path.line(to: NSPoint(x: x, y: 770))
    path.lineWidth = 8
    NSColor(calibratedWhite: 1, alpha: 0.13).setStroke()
    path.stroke()
}

for row in 1...3 {
    let y = 310 + CGFloat(row - 1) * 158
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 238, y: y))
    path.line(to: NSPoint(x: 786, y: y))
    path.lineWidth = 8
    NSColor(calibratedWhite: 1, alpha: 0.13).setStroke()
    path.stroke()
}

let compassCenter = NSPoint(x: 525, y: 523)
let compassRing = NSBezierPath(ovalIn: NSRect(x: 300, y: 298, width: 450, height: 450))
NSColor(calibratedWhite: 1, alpha: 0.96).setStroke()
compassRing.lineWidth = 34
compassRing.stroke()

let needle = NSBezierPath()
needle.move(to: NSPoint(x: compassCenter.x + 118, y: compassCenter.y + 145))
needle.line(to: NSPoint(x: compassCenter.x + 12, y: compassCenter.y - 28))
needle.line(to: NSPoint(x: compassCenter.x - 126, y: compassCenter.y - 151))
needle.line(to: NSPoint(x: compassCenter.x - 16, y: compassCenter.y + 30))
needle.close()
colors.highlight.setFill()
needle.fill()

let needleInset = NSBezierPath()
needleInset.move(to: NSPoint(x: compassCenter.x + 90, y: compassCenter.y + 110))
needleInset.line(to: NSPoint(x: compassCenter.x + 12, y: compassCenter.y - 28))
needleInset.line(to: NSPoint(x: compassCenter.x - 93, y: compassCenter.y - 111))
needleInset.line(to: NSPoint(x: compassCenter.x - 14, y: compassCenter.y + 27))
needleInset.close()
NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
needleInset.fill()

for point in [NSPoint(x: 284, y: 239), NSPoint(x: 738, y: 781)] {
    let dot = NSBezierPath(ovalIn: NSRect(x: point.x - 25, y: point.y - 25, width: 50, height: 50))
    colors.highlight.setFill()
    dot.fill()
}

NSGraphicsContext.restoreGraphicsState()

guard
    let renderedImage = bitmapContext.makeImage(),
    let png = NSBitmapImageRep(cgImage: renderedImage).representation(using: .png, properties: [:])
else {
    fputs("Unable to encode icon\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
} catch {
    fputs("Unable to write icon: \(error.localizedDescription)\n", stderr)
    exit(1)
}
