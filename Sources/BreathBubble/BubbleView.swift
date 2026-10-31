import AppKit

/// A colour for the bubble: a light centre fading to a deeper edge.
struct BubbleColor {
    let id: String
    let name: String
    let light: NSColor
    let deep: NSColor

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }

    static let all: [BubbleColor] = [
        BubbleColor(id: "sea", name: "Sea", light: rgb(0.78, 0.94, 0.95), deep: rgb(0.40, 0.72, 0.80)),
        BubbleColor(id: "sky", name: "Sky", light: rgb(0.80, 0.89, 1.00), deep: rgb(0.38, 0.58, 0.90)),
        BubbleColor(id: "lavender", name: "Lavender", light: rgb(0.90, 0.86, 1.00), deep: rgb(0.60, 0.50, 0.85)),
        BubbleColor(id: "sage", name: "Sage", light: rgb(0.86, 0.94, 0.84), deep: rgb(0.47, 0.66, 0.48)),
        BubbleColor(id: "sand", name: "Sand", light: rgb(1.00, 0.93, 0.80), deep: rgb(0.88, 0.66, 0.40)),
        BubbleColor(id: "rose", name: "Rose", light: rgb(1.00, 0.87, 0.89), deep: rgb(0.88, 0.52, 0.60)),
        BubbleColor(id: "stone", name: "Stone", light: rgb(0.93, 0.93, 0.93), deep: rgb(0.55, 0.57, 0.60)),
    ]

    static func named(_ id: String) -> BubbleColor { all.first { $0.id == id } ?? all[0] }
}

/// Draws the breathing bubble: a faint ring for full size and a soft filled circle that grows and shrinks.
final class BubbleView: NSView {
    var level: Double = 0 { didSet { needsDisplay = true } }
    var color = BubbleColor.all[0] { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let maxR = side / 2 - 3
        let minR = maxR * 0.35
        let r = minR + (maxR - minR) * CGFloat(level)

        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - maxR, y: center.y - maxR, width: maxR * 2, height: maxR * 2))
        ring.lineWidth = 1.5
        color.deep.withAlphaComponent(0.55).setStroke()
        ring.stroke()

        let fill = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        let gradient = NSGradient(colors: [color.light.withAlphaComponent(0.95), color.deep.withAlphaComponent(0.80)])
        gradient?.draw(in: fill, relativeCenterPosition: NSPoint(x: -0.25, y: 0.3))
    }
}
