import AppKit

/// Draws the breathing bubble: a faint ring for full size and a soft filled circle that grows and shrinks.
final class BubbleView: NSView {
    var level: Double = 0 { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let maxR = side / 2 - 3
        let minR = maxR * 0.35
        let r = minR + (maxR - minR) * CGFloat(level)

        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - maxR, y: center.y - maxR, width: maxR * 2, height: maxR * 2))
        ring.lineWidth = 1.5
        NSColor(calibratedRed: 0.55, green: 0.80, blue: 0.85, alpha: 0.55).setStroke()
        ring.stroke()

        let fill = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.78, green: 0.94, blue: 0.95, alpha: 0.95),
            NSColor(calibratedRed: 0.40, green: 0.72, blue: 0.80, alpha: 0.80),
        ])
        gradient?.draw(in: fill, relativeCenterPosition: NSPoint(x: -0.25, y: 0.3))
    }
}
