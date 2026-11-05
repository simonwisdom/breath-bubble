import AppKit

/// A full-screen layer that fills with black and holds only the bubble. Any key or a double-click ends it.
final class FocusView: NSView {
    var dim: CGFloat = 0 { didSet { needsDisplay = true } }
    var onExit: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(dim).setFill()
        bounds.fill()
    }
    override func keyDown(with event: NSEvent) { onExit?() }
    override func mouseDown(with event: NSEvent) { if event.clickCount >= 2 { onExit?() } }
}

final class FocusWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Runs focus mode: fill every screen with black, glide the bubble to the centre, and back again.
/// The screen with the bubble fills in the chosen style; other screens fade in step with it.
final class Focus {
    private enum Phase { case entering, holding, leaving }

    private var windows: [FocusWindow] = []
    private var views: [FocusView] = []
    private var ink: InkLayer?
    private var bubble: BubbleView?
    private var phase = Phase.holding
    private var started = Date()
    private var lastTick = Date()
    /// 0 is the desktop as it was, 1 is fully in focus. Entering and leaving move it up and down.
    private var progress = 0.0
    /// Where progress stood when leaving began; Tide and Ink keep that shape and fade it out.
    private var leaveFrom = 1.0
    /// How far in the screen looked when leaving began, so leaving starts without a jump.
    private var shownAtLeave = 1.0
    private var from = NSRect.zero, to = NSRect.zero
    private var screenSize = NSSize.zero
    private var fromAlpha: CGFloat = 1
    private var previousApp: NSRunningApplication?
    private var onDone: (() -> Void)?

    private var style = FocusStyle.tide
    /// Going in takes a second and a half; coming out is a little quicker.
    private let enterSeconds = 1.5
    private let leaveSeconds = 1.05

    var isActive: Bool { !windows.isEmpty }

    /// Starts focus. `bubbleFrame` is where the floating bubble sits now, in screen coordinates.
    func start(bubbleFrame: NSRect, color: BubbleColor, opacity: CGFloat, style: FocusStyle,
               onDone: @escaping () -> Void) {
        guard !isActive else { return }
        self.onDone = onDone
        // With Reduce motion on, keep to the plain fade.
        self.style = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .fade : style
        previousApp = NSWorkspace.shared.frontmostApplication
        let home = NSScreen.screens.first { $0.frame.intersects(bubbleFrame) } ?? NSScreen.main ?? NSScreen.screens[0]

        for screen in NSScreen.screens {
            let window = FocusWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver  // above the menu bar and the Dock
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            // Hidden from screen shares; BREATHBUBBLE_CAPTURE=1 lets tests take screenshots.
            if ProcessInfo.processInfo.environment["BREATHBUBBLE_CAPTURE"] == nil { window.sharingType = .none }
            let view = FocusView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onExit = { [weak self] in self?.leave() }
            window.contentView = view
            if screen == home {
                screenSize = screen.frame.size
                if self.style != .fade, let layer = InkLayer(size: view.bounds.size) {
                    view.addSubview(layer)
                    ink = layer
                }
                let b = BubbleView()
                b.color = color
                from = NSRect(x: bubbleFrame.minX - screen.frame.minX, y: bubbleFrame.minY - screen.frame.minY,
                              width: bubbleFrame.width, height: bubbleFrame.height)
                let side = min(screen.frame.width, screen.frame.height) * 0.5
                to = NSRect(x: (screen.frame.width - side) / 2, y: (screen.frame.height - side) / 2, width: side, height: side)
                b.frame = from
                b.alphaValue = opacity
                fromAlpha = opacity
                view.addSubview(b)
                bubble = b
            }
            window.orderFrontRegardless()
            windows.append(window)
            views.append(view)
        }
        NSApp.activate(ignoringOtherApps: true)
        if let homeIndex = NSScreen.screens.firstIndex(of: home) {
            windows[homeIndex].makeKeyAndOrderFront(nil)
            windows[homeIndex].makeFirstResponder(views[homeIndex])
        }
        progress = 0
        phase = .entering
        started = Date()
        lastTick = started
        apply()
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    /// Leaves focus. Leaving part-way in starts from where the screen is, without a jump.
    func leave() {
        guard isActive, phase != .leaving else { return }
        leaveFrom = max(progress, 0.001)
        shownAtLeave = Curve.arrive(progress)
        phase = .leaving
    }

    /// Ends at once, with no animation (for example when the screen locks).
    func endNow() {
        guard isActive else { return }
        finish()
    }

    /// Called every frame with the current breath level.
    func tick(level: Double) {
        guard isActive else { return }
        bubble?.level = level
        let now = Date()
        let dt = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now
        switch phase {
        case .entering:
            progress = min(1, progress + dt / enterSeconds)
            apply()
            if progress >= 1 { phase = .holding }
        case .holding:
            break  // nothing changes, so nothing is drawn
        case .leaving:
            progress = max(0, progress - dt / leaveSeconds)
            apply()
            if progress <= 0 { finish() }
        }
    }

    private func apply() {
        // Tide and Ink keep their shape while leaving and fade it out.
        let fadeOut = phase == .leaving ? 1 - Curve.leave(1 - progress / leaveFrom) : 1
        let e = phase == .leaving ? shownAtLeave * fadeOut : Curve.arrive(progress)
        // The screen with the ink layer is drawn by it; every other screen dims evenly.
        for v in views where ink?.superview !== v { v.dim = CGFloat(e) }
        // The bubble moves a little behind the fill, so the dark arrives first.
        let m = CGFloat(ease(min(1, max(0, (e - 0.15) / 0.85))))
        let frame = NSRect(x: from.minX + (to.minX - from.minX) * m, y: from.minY + (to.minY - from.minY) * m,
                           width: from.width + (to.width - from.width) * m,
                           height: from.height + (to.height - from.height) * m)
        bubble?.frame = frame
        bubble?.alphaValue = fromAlpha + (1 - fromAlpha) * m

        guard let ink, screenSize.height > 0 else { return }
        let w = Float(screenSize.width), h = Float(screenSize.height)
        let aspect = w / h
        func point(_ r: NSRect) -> SIMD2<Float> { SIMD2(Float(r.midX) / w, Float(r.midY) / h) }
        func farthest(_ p: SIMD2<Float>) -> Float {
            [SIMD2<Float>(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)]
                .map { (($0.x - p.x) * aspect * ($0.x - p.x) * aspect + ($0.y - p.y) * ($0.y - p.y)).squareRoot() }
                .max() ?? 1
        }
        var u = ink.uniforms
        u.bubble = point(frame)
        u.origin = point(from)
        u.aspect = aspect
        u.time = Float(Date().timeIntervalSince(started))
        u.progress = Float(phase == .leaving ? shownAtLeave : e)
        u.fade = Float(fadeOut)
        u.maxFromBubble = farthest(u.bubble)
        u.maxFromOrigin = farthest(u.origin)
        u.mode = style == .ink ? 2 : 1
        ink.uniforms = u
        ink.render()
    }

    private func finish() {
        for w in windows { w.orderOut(nil) }
        windows = []
        views = []
        ink = nil
        bubble = nil
        previousApp?.activate()
        previousApp = nil
        onDone?()
        onDone = nil
    }

    private func ease(_ p: Double) -> Double { (1 - cos(Double.pi * p)) / 2 }
}
