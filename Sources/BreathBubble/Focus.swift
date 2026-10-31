import AppKit

/// A full-screen layer that fades to black and holds only the bubble. Any key or a double-click ends it.
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

/// Runs focus mode: fade every screen to black, glide the bubble to the centre, and back again.
final class Focus {
    private enum Phase { case entering, holding, leaving }

    private var windows: [FocusWindow] = []
    private var views: [FocusView] = []
    private var bubble: BubbleView?
    private var phase = Phase.holding
    private var phaseStart = Date()
    private var from = NSRect.zero, to = NSRect.zero
    private var fromAlpha: CGFloat = 1
    private var previousApp: NSRunningApplication?
    private var onDone: (() -> Void)?

    private let enterSeconds = 2.5
    private let leaveSeconds = 0.9

    var isActive: Bool { !windows.isEmpty }

    /// Starts focus. `bubbleFrame` is where the floating bubble sits now, in screen coordinates.
    func start(bubbleFrame: NSRect, color: BubbleColor, opacity: CGFloat, onDone: @escaping () -> Void) {
        guard !isActive else { return }
        self.onDone = onDone
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
        phase = .entering
        phaseStart = Date()
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func leave() {
        guard isActive, phase != .leaving else { return }
        phase = .leaving
        phaseStart = Date()
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
        let t = Date().timeIntervalSince(phaseStart)
        switch phase {
        case .entering:
            let p = min(1, t / enterSeconds)
            apply(ease(p))
            if p >= 1 { phase = .holding }
        case .holding:
            break
        case .leaving:
            let p = min(1, t / leaveSeconds)
            apply(1 - ease(p))
            if p >= 1 { finish() }
        }
    }

    /// 0 is the desktop as it was, 1 is fully in focus.
    private func apply(_ e: Double) {
        let k = CGFloat(e)
        for v in views { v.dim = k }
        // The bubble moves a little behind the fade, so the dark arrives first.
        let m = CGFloat(ease(min(1, max(0, (e - 0.15) / 0.85))))
        bubble?.frame = NSRect(x: from.minX + (to.minX - from.minX) * m, y: from.minY + (to.minY - from.minY) * m,
                               width: from.width + (to.width - from.width) * m,
                               height: from.height + (to.height - from.height) * m)
        bubble?.alphaValue = fromAlpha + (1 - fromAlpha) * m
    }

    private func finish() {
        for w in windows { w.orderOut(nil) }
        windows = []
        views = []
        bubble = nil
        previousApp?.activate()
        previousApp = nil
        onDone?()
        onDone = nil
    }

    private func ease(_ p: Double) -> Double { (1 - cos(Double.pi * p)) / 2 }
}
