import AppKit
import SwiftUI
import AVFoundation

/// A borderless panel that floats over every app and Space, including full-screen ones.
final class FloatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var panel: FloatPanel!
    private let popover = NSPopover()
    private let bubble = BubbleView()
    private let sound = Sound()
    private var timer: Timer?
    private var tickRate = 0.0
    private let focus = Focus()

    /// Read from settings in applySettings, so the timer doesn't read them on every tick.
    private var pace = Pace.all[0]
    private var clickThrough = true
    /// The rhythm the floating bubble was last told to breathe, so it's only restarted when that changes.
    private var breathing = ""

    private var doubleClickFocus: Bool { defaults.object(forKey: "doubleClickFocus") as? Bool ?? true }
    private var colorID: String { defaults.string(forKey: "color") ?? "sea" }
    private var savedPace: Pace {
        Pace.named(defaults.string(forKey: "pace") ?? "slow",
                   breathIn: defaults.object(forKey: "breathIn") as? Double ?? 5.5,
                   breathOut: defaults.object(forKey: "breathOut") as? Double ?? 5.5)
    }
    private var size: CGFloat { CGFloat(defaults.object(forKey: "size") as? Double ?? 110) }
    private var opacity: Double { defaults.object(forKey: "opacity") as? Double ?? 0.6 }
    private var savedClickThrough: Bool { defaults.object(forKey: "clickThrough") as? Bool ?? true }
    private var soundOn: Bool { defaults.bool(forKey: "sound") }
    private var shown: Bool { defaults.object(forKey: "shown") as? Bool ?? true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Breathing bubble")
            button.action = #selector(togglePopover)
            button.target = self
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PanelView())
        makePanel()
        applySettings()
        // The panel writes settings straight to UserDefaults; follow every change.
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        watchAway()
        watchDoubleClick()
        // BREATHBUBBLE_FOCUS_TEST=1 starts focus a second after launch, so a test can watch it without clicking.
        if ProcessInfo.processInfo.environment["BREATHBUBBLE_FOCUS_TEST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.startFocus() }
        }
    }

    // MARK: Focus

    /// A double-click on the bubble starts focus. While clicks pass through, the click goes to the
    /// app underneath, so watch for it there (mouse clicks need no permission to watch); while the
    /// bubble catches the mouse, the click arrives in this app.
    private func watchDoubleClick() {
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.clickCount == 2, self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.startFocus()
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let self, event.window === self.panel, event.clickCount == 2 { self.startFocus() }
            return event
        }
        // Lets a script or Shortcut start and end focus, and lets tests do it without clicking.
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(self, selector: #selector(focusRequested), name: .init("com.simonwisdom.breathbubble.focus"),
                       object: nil, suspensionBehavior: .deliverImmediately)
        dc.addObserver(self, selector: #selector(unfocusRequested), name: .init("com.simonwisdom.breathbubble.unfocus"),
                       object: nil, suspensionBehavior: .deliverImmediately)
    }

    @objc private func focusRequested() { startFocus() }
    @objc private func unfocusRequested() { focus.leave() }

    private func startFocus() {
        guard doubleClickFocus, panel.isVisible, !focus.isActive else { return }
        if popover.isShown { popover.performClose(nil) }
        focus.start(bubbleFrame: panel.frame, color: BubbleColor.named(colorID), opacity: CGFloat(opacity),
                    style: FocusStyle.named(defaults.string(forKey: "focusStyle"))) { [weak self] in
            self?.applySettings()
        }
        applySettings()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func settingsChanged() {
        DispatchQueue.main.async { self.applySettings() }
    }

    // MARK: Pause while away

    private var away = false

    /// Hides the bubble and stops the sound while the screen is locked, asleep or the Mac sleeps.
    private func watchAway() {
        let ws = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            ws.addObserver(self, selector: #selector(wentAway), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(self, selector: #selector(cameBack), name: name, object: nil)
        }
        // A menu bar app is never the active app, and macOS holds distributed notifications
        // for inactive apps unless they ask for immediate delivery.
        dc.addObserver(self, selector: #selector(wentAway), name: .init("com.apple.screenIsLocked"), object: nil,
                       suspensionBehavior: .deliverImmediately)
        dc.addObserver(self, selector: #selector(cameBack), name: .init("com.apple.screenIsUnlocked"), object: nil,
                       suspensionBehavior: .deliverImmediately)
    }

    @objc private func wentAway() {
        away = true
        // Core Animation's clock stops while the Mac sleeps; start the breathing afresh on return so it keeps in step.
        breathing = ""
        focus.endNow()
        applySettings()
    }

    @objc private func cameBack() {
        // Waking the screen shows the lock screen first; stay paused until it's unlocked.
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           session["CGSSessionScreenIsLocked"] as? Bool == true { return }
        away = false
        applySettings()
    }

    // MARK: The floating bubble

    private func makePanel() {
        panel = FloatPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        // Left out of screen shares and recordings; BREATHBUBBLE_CAPTURE=1 lets tests take screenshots.
        if ProcessInfo.processInfo.environment["BREATHBUBBLE_CAPTURE"] == nil { panel.sharingType = .none }
        panel.delegate = self
        panel.contentView = bubble
        if let saved = defaults.string(forKey: "origin") {
            panel.setFrameOrigin(NSPointFromString(saved))
        } else if let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - size - 24, y: v.minY + 24))
        }
    }

    func windowDidMove(_ notification: Notification) {
        let saved = NSStringFromPoint(panel.frame.origin)
        if defaults.string(forKey: "origin") != saved { defaults.set(saved, forKey: "origin") }
    }

    /// The floating bubble breathes by itself (Core Animation), so the timer only needs to run fast
    /// while focus draws its frames; otherwise it keeps the sound and the ⌘ check up to date.
    private func setTickRate(_ perSecond: Double) {
        guard perSecond != tickRate else { return }
        tickRate = perSecond
        timer?.invalidate()
        timer = Timer(timeInterval: 1 / perSecond, repeats: true) { [weak self] _ in self?.tick() }
        timer!.tolerance = 0.2 / perSecond
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        let level = pace.level(at: Date().timeIntervalSince(breathStart))
        focus.tick(level: level)
        sound.level = level
        // Holding ⌘ lets the bubble catch the mouse so it can be dragged, even while clicks pass through.
        let catchesMouse = !clickThrough || NSEvent.modifierFlags.contains(.command)
        if panel.ignoresMouseEvents == catchesMouse { panel.ignoresMouseEvents = !catchesMouse }
    }

    private func applySettings() {
        if abs(panel.frame.width - size) > 0.5 {
            var frame = panel.frame
            let center = NSPoint(x: frame.midX, y: frame.midY)
            frame.size = NSSize(width: size, height: size)
            frame.origin = NSPoint(x: center.x - size / 2, y: center.y - size / 2)
            panel.setFrame(frame, display: true)
        }
        panel.alphaValue = opacity
        bubble.color = BubbleColor.named(colorID)
        pace = savedPace
        clickThrough = savedClickThrough
        let rhythm = pace.steps.map { "\($0)" }.joined(separator: " ")
        if rhythm != breathing {
            breathing = rhythm
            bubble.breathe(pace, since: breathStart)
        }
        let visible = shown && !away
        let floating = visible && !focus.isActive  // in focus, the focus layer shows the bubble instead
        if floating && !panel.isVisible { panel.orderFrontRegardless() }
        if !floating && panel.isVisible { panel.orderOut(nil) }
        sound.volume = defaults.object(forKey: "volume") as? Double ?? 0.6
        sound.followBreath = defaults.object(forKey: "followBreath") as? Bool ?? true
        sound.choose(defaults.string(forKey: "soundChoice") ?? "waves")
        if soundOn && visible { if !sound.isRunning { sound.start() } } else if sound.isRunning { sound.stop() }
        setTickRate(focus.isActive ? 60 : sound.isRunning ? 30 : 10)
    }
}

// Draws the settings panel (light and dark) and each bubble colour to PNGs and exits,
// for checking the look without opening anything on screen. It reads the saved settings but never writes them.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--snapshot" {
    let dir = URL(fileURLWithPath: CommandLine.arguments[2])
    func save(_ view: NSView, _ name: String) {
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
    }
    for (name, look) in [("panel-light.png", NSAppearance.Name.aqua), ("panel-dark.png", .darkAqua)] {
        let host = NSHostingView(rootView: PanelView().background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: look)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        save(host, name)
    }
    // The bubble is drawn in layers, which caching a view's display leaves out, so render the layers.
    let stripWidth = BubbleColor.all.count * 110
    if let ctx = CGContext(data: nil, width: stripWidth * 2, height: 220, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
        ctx.scaleBy(x: 2, y: 2)
        for (n, color) in BubbleColor.all.enumerated() {
            let v = BubbleView(frame: NSRect(x: 0, y: 0, width: 110, height: 110))
            v.color = color
            v.level = 0.6
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(n * 110), y: 0)
            v.layer?.render(in: ctx)
            ctx.restoreGState()
        }
        if let image = ctx.makeImage() {
            try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                .write(to: dir.appendingPathComponent("colours.png"))
        }
    }
    // Each focus style at five moments going in, over a light background, bubble starting top right.
    let (fw, fh) = (320, 200)
    for style in [FocusStyle.tide, .ink] {
        guard let ctx = CGContext(data: nil, width: fw * 5, height: fh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        ctx.setFillColor(NSColor(calibratedRed: 0.85, green: 0.78, blue: 0.86, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: fw * 5, height: fh))
        for n in 0..<5 {
            let p = Float(n + 1) / 5
            let e = 0.5 - 0.5 * cos(Float.pi * p)
            var u = InkUniforms()
            u.origin = SIMD2(0.86, 0.8)
            u.bubble = u.origin + (SIMD2(0.5, 0.5) - u.origin) * e
            u.aspect = Float(fw) / Float(fh)
            u.time = p * 2.5
            u.progress = p
            u.maxFromBubble = 1.25
            u.maxFromOrigin = 1.6
            u.mode = style == .ink ? 2 : 1
            if let frame = InkLayer.snapshot(u, width: fw, height: fh) {
                ctx.draw(frame, in: CGRect(x: n * fw, y: 0, width: fw, height: fh))
            }
        }
        if let image = ctx.makeImage() {
            try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                .write(to: dir.appendingPathComponent("focus-\(style.rawValue).png"))
        }
    }
    exit(0)
}

// Prints each sound and how many seconds of it load, without playing anything.
if CommandLine.arguments.dropFirst().first == "--check-sounds" {
    for choice in SoundChoice.all {
        guard let path = choice.file else { print("\(choice.name): made here"); continue }
        let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path))
        print("\(choice.name): \(file.map { String(format: "%.1f s", Double($0.length) / $0.processingFormat.sampleRate) } ?? "FAILED")")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
