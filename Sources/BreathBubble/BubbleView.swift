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

/// The breathing bubble: a faint ring for full size and a soft filled circle that grows and shrinks.
/// The circle is drawn once at full size and scaled by Core Animation, so breathing costs the app
/// almost nothing: `breathe` hands the whole rhythm to Core Animation, and `level` sets one moment.
final class BubbleView: NSView {
    var level: Double = 0 { didSet { showLevel() } }
    var color = BubbleColor.all[0] { didSet { if color.id != oldValue.id { redraw() } } }

    /// Smallest size of the filled circle, as a share of the ring.
    static let smallest = 0.35

    private let ring = CAShapeLayer()
    private let fill = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(ring)
        layer?.addSublayer(fill)
        redraw()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isOpaque: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { redraw() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redraw()
    }

    /// Breathes on its own at `pace`, in step with a rhythm that began at `start`, until `level` is set.
    func breathe(_ pace: Pace, since start: Date) {
        let samples = 240
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = (0...samples).map { scale(pace.level(at: Double($0) / Double(samples) * pace.cycle)) }
        animation.duration = pace.cycle
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        let into = Date().timeIntervalSince(start).truncatingRemainder(dividingBy: pace.cycle)
        animation.beginTime = fill.convertTime(CACurrentMediaTime(), from: nil) - into
        fill.add(animation, forKey: "breathe")
    }

    private func scale(_ level: Double) -> Double { Self.smallest + (1 - Self.smallest) * level }

    private func showLevel() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.removeAnimation(forKey: "breathe")
        fill.setAffineTransform(CGAffineTransform(scaleX: scale(level), y: scale(level)))
        CATransaction.commit()
    }

    /// Draws the ring and the full-size circle again, for a new size, colour or screen.
    private func redraw() {
        let side = min(bounds.width, bounds.height)
        let maxR = side / 2 - 3
        guard maxR > 0 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let light = color.light, deep = color.deep
        let disc = NSImage(size: NSSize(width: maxR * 2, height: maxR * 2), flipped: false) { rect in
            let gradient = NSGradient(colors: [light.withAlphaComponent(0.95), deep.withAlphaComponent(0.80)])
            gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: NSPoint(x: -0.25, y: 0.3))
            return true
        }
        let screenScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ring.path = CGPath(ellipseIn: CGRect(x: center.x - maxR, y: center.y - maxR, width: maxR * 2, height: maxR * 2),
                           transform: nil)
        ring.lineWidth = 1.5
        ring.fillColor = nil
        ring.strokeColor = deep.withAlphaComponent(0.55).cgColor
        ring.contentsScale = screenScale
        fill.bounds = CGRect(x: 0, y: 0, width: maxR * 2, height: maxR * 2)
        fill.position = center
        fill.contentsScale = screenScale
        fill.contents = disc.layerContents(forContentsScale: screenScale)
        CATransaction.commit()
    }
}
