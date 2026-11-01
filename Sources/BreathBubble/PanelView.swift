import AppKit
import ServiceManagement
import SwiftUI

/// When the breathing clock started; the bubble and the panel's preview share it so they move together.
let breathStart = Date()

/// The panel that opens from the menu bar icon. Settings live in UserDefaults; the app watches them.
struct PanelView: View {
    @AppStorage("shown") private var shown = true
    @AppStorage("pace") private var paceID = "slow"
    @AppStorage("size") private var size = 110.0
    @AppStorage("opacity") private var opacity = 0.6
    @AppStorage("color") private var colorID = "sea"
    @AppStorage("sound") private var sound = false
    @AppStorage("soundChoice") private var soundChoice = "waves"
    @AppStorage("volume") private var volume = 0.6
    @AppStorage("followBreath") private var followBreath = true
    @AppStorage("clickThrough") private var clickThrough = true
    @AppStorage("doubleClickFocus") private var doubleClickFocus = true
    @AppStorage("focusStyle") private var focusStyle = FocusStyle.tide.rawValue
    @AppStorage("breathIn") private var breathIn = 5.5
    @AppStorage("breathOut") private var breathOut = 5.5
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    private var color: BubbleColor { BubbleColor.named(colorID) }
    private var pace: Pace { Pace.named(paceID, breathIn: breathIn, breathOut: breathOut) }
    private var tint: Color { Color(nsColor: color.deep) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            section("Pace") { paces }
            section("Look") { look }
            section("Sound") { soundControls }
            section("Options") { options }
            footer
        }
        .padding(16)
        .frame(width: 300)
        .tint(tint)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 12) {
            Preview(color: color, pace: pace)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Breath Bubble").font(.system(size: 15, weight: .semibold))
                Text(shown ? "Bubble on screen" : "Bubble hidden")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $shown).toggleStyle(.switch).labelsHidden()
        }
    }

    private var paces: some View {
        VStack(spacing: 8) {
            paceCards
            secondsRow("In", Binding(get: { pace.inSeconds }, set: { makeCustom(); breathIn = $0 }), 2...10)
            secondsRow("Out", Binding(get: { pace.outSeconds }, set: { makeCustom(); breathOut = $0 }), 2...12)
        }
    }

    /// Moving a length slider switches to Custom, starting from the chosen pace's lengths.
    private func makeCustom() {
        guard paceID != "custom" else { return }
        breathIn = pace.inSeconds
        breathOut = pace.outSeconds
        paceID = "custom"
    }

    private var paceCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Pace.all, id: \.id) { p in
                let on = p.id == paceID
                Button { paceID = p.id } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 13, weight: .medium))
                        Text(p.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(on ? tint.opacity(0.18) : Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? tint.opacity(0.8) : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var look: some View {
        VStack(spacing: 12) {
            sliderRow("Size", $size, 50...240)
            sliderRow("Opacity", $opacity, 0.15...1)
            HStack(spacing: 0) {
                ForEach(BubbleColor.all, id: \.id) { c in
                    Button { colorID = c.id } label: { Dot(color: c, chosen: c.id == colorID) }
                        .buttonStyle(.plain)
                        .help(c.name)
                        .accessibilityLabel(c.name)
                    if c.id != BubbleColor.all.last?.id { Spacer(minLength: 0) }
                }
            }
        }
    }

    private var soundControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("", selection: $soundChoice) {
                    ForEach(SoundChoice.all, id: \.id) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $sound).toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            Group {
                sliderRow("Volume", $volume, 0...1)
                row("lungs", "Rise and fall with breath", $followBreath)
            }
            .disabled(!sound)
            .opacity(sound ? 1 : 0.45)
        }
    }

    private var options: some View {
        VStack(spacing: 8) {
            row("moon", "Double-click for focus", $doubleClickFocus)
            focusControls
                .disabled(!doubleClickFocus)
                .opacity(doubleClickFocus ? 1 : 0.45)
            row("cursorarrow.motionlines", "Clicks pass through", $clickThrough)
            row("power", "Open at login", Binding(get: { openAtLogin }, set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch { NSLog("Open at login failed: \(error)") }
                openAtLogin = SMAppService.mainApp.status == .enabled
            }))
        }
    }

    /// How focus fills the screen.
    private var focusControls: some View {
        HStack(spacing: 10) {
                Picker("", selection: $focusStyle) {
                    ForEach(FocusStyle.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button("Try") {
                    DistributedNotificationCenter.default().postNotificationName(
                        .init("com.simonwisdom.breathbubble.focus"), object: nil, userInfo: nil, deliverImmediately: true)
                }
                .controlSize(.small)
                .help("Start focus now; any key or a double-click comes back")
        }
        .padding(.leading, 28)
    }

    private var footer: some View {
        HStack {
            Text("Hold ⌘ and drag the bubble to move it")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).kerning(0.6).foregroundStyle(.secondary)
            content()
        }
    }

    private func sliderRow(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13)).frame(width: 58, alignment: .leading)
            Slider(value: value, in: range)
        }
    }

    private func secondsRow(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13)).frame(width: 30, alignment: .leading)
            Slider(value: Binding(get: { value.wrappedValue },
                                  set: { value.wrappedValue = ($0 * 10).rounded() / 10 }), in: range)
            Text(String(format: "%.1f s", value.wrappedValue))
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func row(_ icon: String, _ title: String, _ value: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            Text(title).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: value).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }
}

/// A small live copy of the bubble, breathing in time with the real one.
private struct Preview: View {
    let color: BubbleColor
    let pace: Pace

    var body: some View {
        TimelineView(.animation) { context in
            let level = pace.level(at: context.date.timeIntervalSince(breathStart))
            ZStack {
                Circle().strokeBorder(Color(nsColor: color.deep).opacity(0.5), lineWidth: 1.2)
                Circle()
                    .fill(RadialGradient(colors: [Color(nsColor: color.light), Color(nsColor: color.deep)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 26))
                    .scaleEffect(0.35 + 0.6 * level)
            }
        }
    }
}

/// One colour choice: a soft dot, with a ring when chosen.
private struct Dot: View {
    let color: BubbleColor
    let chosen: Bool

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(nsColor: color.light), Color(nsColor: color.deep)],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 14))
            .frame(width: 22, height: 22)
            .padding(3)
            .overlay(Circle().strokeBorder(chosen ? Color.primary.opacity(0.55) : .clear, lineWidth: 1.5))
            .contentShape(Circle())
    }
}
