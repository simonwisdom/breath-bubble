import AppKit
import SwiftUI

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

    private var colorID: String { defaults.string(forKey: "color") ?? "sea" }
    private var pace: Pace { Pace.named(defaults.string(forKey: "pace") ?? "slow") }
    private var size: CGFloat { CGFloat(defaults.object(forKey: "size") as? Double ?? 110) }
    private var opacity: Double { defaults.object(forKey: "opacity") as? Double ?? 0.6 }
    private var clickThrough: Bool { defaults.object(forKey: "clickThrough") as? Bool ?? true }
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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        watchAway()
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

    @objc private func wentAway() { away = true; applySettings() }

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
        let saved = NSStringFromPoint(panel.frame.origin)
        if defaults.string(forKey: "origin") != saved { defaults.set(saved, forKey: "origin") }
    }

    private func tick() {
        let level = pace.level(at: Date().timeIntervalSince(breathStart))
        if panel.isVisible { bubble.level = level }
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
        let visible = shown && !away
        if visible && !panel.isVisible { panel.orderFrontRegardless() }
        if !visible && panel.isVisible { panel.orderOut(nil) }
        if soundOn && visible { if !sound.isRunning { sound.start() } } else if sound.isRunning { sound.stop() }
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
    let strip = NSView(frame: NSRect(x: 0, y: 0, width: CGFloat(BubbleColor.all.count) * 110, height: 110))
    for (n, color) in BubbleColor.all.enumerated() {
        let v = BubbleView(frame: NSRect(x: CGFloat(n) * 110, y: 0, width: 110, height: 110))
        v.level = 0.6
        v.color = color
        strip.addSubview(v)
    }
    save(strip, "colours.png")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
