import AppKit
import ServiceManagement

/// A borderless panel that floats over every app and Space, including full-screen ones.
final class FloatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var panel: FloatPanel!
    private let bubble = BubbleView()
    private let sound = Sound()
    private var timer: Timer?
    private let start = Date()

    private let sizes: [(String, CGFloat)] = [("Small", 70), ("Medium", 110), ("Large", 170)]
    private let opacities: [(String, Double)] = [("Faint", 0.3), ("Soft", 0.6), ("Clear", 0.9)]

    private var pace: Pace { Pace.named(defaults.string(forKey: "pace") ?? "slow") }
    private var size: CGFloat { CGFloat(defaults.object(forKey: "size") as? Double ?? 110) }
    private var opacity: Double { defaults.object(forKey: "opacity") as? Double ?? 0.6 }
    private var clickThrough: Bool { defaults.object(forKey: "clickThrough") as? Bool ?? true }
    private var soundOn: Bool { defaults.bool(forKey: "sound") }
    private var shown: Bool { defaults.object(forKey: "shown") as? Bool ?? true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Breathing bubble")
        makePanel()
        rebuildMenu()
        applySettings()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        watchAway()
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

    @objc private func wentAway() { away = true; applySettings() }

    @objc private func cameBack() {
        // Waking the screen shows the lock screen first; stay paused until it's unlocked.
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           session["CGSSessionScreenIsLocked"] as? Bool == true { return }
        away = false
        applySettings()
    }

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
        panel.sharingType = .none  // left out of screen shares and recordings
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
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: "origin")
    }

    private func tick() {
        let level = pace.level(at: Date().timeIntervalSince(start))
        if panel.isVisible { bubble.level = level }
        sound.level = level
        // Holding ⌘ lets the bubble catch the mouse so it can be dragged, even while clicks pass through.
        let catchesMouse = !clickThrough || NSEvent.modifierFlags.contains(.command)
        if panel.ignoresMouseEvents == catchesMouse { panel.ignoresMouseEvents = !catchesMouse }
    }

    private func applySettings() {
        var frame = panel.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = NSSize(width: size, height: size)
        frame.origin = NSPoint(x: center.x - size / 2, y: center.y - size / 2)
        panel.setFrame(frame, display: true)
        panel.alphaValue = opacity
        if shown && !away { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        if soundOn && shown && !away { sound.start() } else { sound.stop() }
        rebuildMenu()
    }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(item(shown ? "Hide bubble" : "Show bubble", #selector(toggleShown), key: "b"))
        menu.addItem(header("Hold ⌘ and drag the bubble to move it"))
        menu.addItem(.separator())

        menu.addItem(header("Pace"))
        for p in Pace.all {
            let i = item(p.title, #selector(pickPace(_:)))
            i.representedObject = p.id
            i.state = p.id == pace.id ? .on : .off
            menu.addItem(i)
        }
        menu.addItem(.separator())

        menu.addItem(submenu("Size", sizes.map { ($0.0, Double($0.1)) }, current: Double(size), action: #selector(pickSize(_:))))
        menu.addItem(submenu("Opacity", opacities, current: opacity, action: #selector(pickOpacity(_:))))

        let soundItem = item("Wave sound", #selector(toggleSound))
        soundItem.state = soundOn ? .on : .off
        menu.addItem(soundItem)

        let through = item("Clicks pass through", #selector(toggleClickThrough))
        through.state = clickThrough ? .on : .off
        through.toolTip = "Hold ⌘ to drag the bubble either way."
        menu.addItem(through)

        let login = item("Open at login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func header(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func submenu(_ title: String, _ options: [(String, Double)], current: Double, action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (name, value) in options {
            let i = item(name, action)
            i.representedObject = value
            i.state = abs(value - current) < 0.001 ? .on : .off
            sub.addItem(i)
        }
        parent.submenu = sub
        return parent
    }

    @objc private func toggleShown() { defaults.set(!shown, forKey: "shown"); applySettings() }
    @objc private func pickPace(_ sender: NSMenuItem) { defaults.set(sender.representedObject as? String, forKey: "pace"); rebuildMenu() }
    @objc private func pickSize(_ sender: NSMenuItem) { defaults.set(sender.representedObject as? Double, forKey: "size"); applySettings() }
    @objc private func pickOpacity(_ sender: NSMenuItem) { defaults.set(sender.representedObject as? Double, forKey: "opacity"); applySettings() }
    @objc private func toggleSound() { defaults.set(!soundOn, forKey: "sound"); applySettings() }
    @objc private func toggleClickThrough() { defaults.set(!clickThrough, forKey: "clickThrough"); applySettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("Open at login failed: \(error)")
        }
        rebuildMenu()
    }
}

// Draws the bubble to a PNG and exits, for checking the look without putting a window on screen.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--snapshot" {
    let view = BubbleView(frame: NSRect(x: 0, y: 0, width: 330, height: 110))
    let strip = NSView(frame: view.frame)
    for (n, level) in [0.0, 0.5, 1.0].enumerated() {
        let v = BubbleView(frame: NSRect(x: CGFloat(n) * 110, y: 0, width: 110, height: 110))
        v.level = level
        strip.addSubview(v)
    }
    let rep = strip.bitmapImageRepForCachingDisplay(in: strip.bounds)!
    strip.cacheDisplay(in: strip.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
