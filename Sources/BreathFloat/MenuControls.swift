import AppKit

private let rowWidth: CGFloat = 260
private let inset: CGFloat = 14

/// A menu row with a small label above a slider.
func sliderItem(_ title: String, min: Double, max: Double, value: Double,
                target: AnyObject, action: Selector) -> NSMenuItem {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: 46))
    let label = NSTextField(labelWithString: title)
    label.font = .menuFont(ofSize: 0)
    label.textColor = .secondaryLabelColor
    label.frame = NSRect(x: inset, y: 26, width: rowWidth - inset * 2, height: 16)
    let slider = NSSlider(value: value, minValue: min, maxValue: max, target: target, action: action)
    slider.isContinuous = true
    slider.controlSize = .small
    slider.frame = NSRect(x: inset, y: 4, width: rowWidth - inset * 2, height: 20)
    view.addSubview(label)
    view.addSubview(slider)
    let item = NSMenuItem()
    item.view = view
    return item
}

/// A round button showing one bubble colour; a ring marks the chosen one.
final class Swatch: NSButton {
    let color: BubbleColor
    var chosen = false { didSet { needsDisplay = true } }

    init(_ color: BubbleColor, target: AnyObject, action: Selector) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        toolTip = color.name
        setAccessibilityLabel(color.name)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let dot = NSBezierPath(ovalIn: bounds.insetBy(dx: 5, dy: 5))
        NSGradient(colors: [color.light, color.deep])?.draw(in: dot, relativeCenterPosition: NSPoint(x: -0.3, y: 0.3))
        if chosen {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 2
            NSColor.labelColor.withAlphaComponent(0.7).setStroke()
            ring.stroke()
        }
    }
}

/// A menu row of colour swatches.
func swatchItem(chosen: String, target: AnyObject, action: Selector) -> NSMenuItem {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: 50))
    let label = NSTextField(labelWithString: "Colour")
    label.font = .menuFont(ofSize: 0)
    label.textColor = .secondaryLabelColor
    label.frame = NSRect(x: inset, y: 30, width: 120, height: 16)
    view.addSubview(label)
    for (n, color) in BubbleColor.all.enumerated() {
        let s = Swatch(color, target: target, action: action)
        s.frame.origin = NSPoint(x: inset - 4 + CGFloat(n) * 32, y: 2)
        s.chosen = color.id == chosen
        view.addSubview(s)
    }
    let item = NSMenuItem()
    item.view = view
    return item
}
