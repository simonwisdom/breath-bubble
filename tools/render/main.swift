// Draws the app icon and the bubble animation frames used by the README.
// Built by tools/make-assets together with the app's BubbleView.swift and Pace.swift.
import AppKit

func savePNG(_ size: NSSize, _ path: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

/// The icon: a deep sea-blue rounded square with a soft glowing bubble inside a faint ring.
func drawIcon(_ s: CGFloat) {
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tile = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = rgb(0, 0.1, 0.2, 0.35)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    rgb(0.1, 0.3, 0.4).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0.20, 0.55, 0.66), rgb(0.07, 0.24, 0.38)])!.draw(in: tile, angle: -90)

    let c = NSPoint(x: rect.midX, y: rect.midY)
    let ringR = rect.width * 0.36
    let ring = NSBezierPath(ovalIn: NSRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2))
    ring.lineWidth = s * 0.012
    rgb(0.75, 0.93, 0.95, 0.45).setStroke()
    ring.stroke()

    let r = rect.width * 0.25
    let ball = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    NSGradient(colors: [rgb(0.92, 0.99, 1.0), rgb(0.55, 0.85, 0.90), rgb(0.32, 0.66, 0.76)])!
        .draw(in: ball, relativeCenterPosition: NSPoint(x: -0.3, y: 0.35))
}

let args = CommandLine.arguments
switch args.count > 2 ? args[1] : "" {
case "icon":
    for px in [16, 32, 64, 128, 256, 512, 1024] {
        savePNG(NSSize(width: px, height: px), "\(args[2])/icon_\(px).png") { drawIcon(CGFloat(px)) }
    }
case "frames":
    // One slow breath (11 s) at 15 frames a second, bubble only, transparent background.
    let pace = Pace.named("slow")
    let count = Int(pace.cycle * 15)
    for i in 0..<count {
        let view = BubbleView(frame: NSRect(x: 0, y: 0, width: 220, height: 220))
        view.level = pace.level(at: Double(i) / 15)
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: String(format: "%@/f%03d.png", args[2], i)))
    }
default:
    print("usage: render icon|frames <folder>")
}
