import AVFoundation

/// A sound the user can pick: the app's own breath waves, or one of macOS's built-in Background Sounds.
struct SoundChoice {
    let id: String
    let name: String
    /// nil for the waves made here.
    let file: String?

    private static let appleFolder = "/System/Library/PrivateFrameworks/HearingUtilities.framework/Versions/A/Resources/"

    static let all: [SoundChoice] = [SoundChoice(id: "waves", name: "Breath waves", file: nil)] + [
        ("ocean", "Ocean", "Ocean"), ("rain", "Rain", "Rain"), ("stream", "Stream", "Stream"),
        ("night", "Night", "Night"), ("fire", "Fire", "Fire"), ("brown", "Brown noise", "BrownNoise"),
        ("pink", "Pink noise", "PinkNoise"), ("white", "White noise", "WhiteNoise"),
    ].compactMap { id, name, file in
        // Apple's files live in a private framework; leave out any a macOS update moves or removes.
        let path = appleFolder + file + ".m4a"
        return FileManager.default.fileExists(atPath: path) ? SoundChoice(id: id, name: name, file: path) : nil
    }

    static func named(_ id: String) -> SoundChoice { all.first { $0.id == id } ?? all[0] }
}

/// Plays the chosen sound. With `followBreath` on, it swells as you breathe in and fades as you breathe out.
final class Sound {
    private let engine = AVAudioEngine()
    private var waves: AVAudioSourceNode?
    private let player = AVAudioPlayerNode()
    private var loadedFile: String?

    /// Set from the main thread; read by the audio thread. A torn read only costs one odd sample.
    var level: Double = 0 { didSet { updatePlayerVolume() } }
    var volume: Double = 0.6 { didSet { updatePlayerVolume() } }
    var followBreath = true { didSet { updatePlayerVolume() } }
    private(set) var choice = SoundChoice.all[0]

    private var gain: Double = 0
    private var brown: Double = 0

    var isRunning: Bool { engine.isRunning }

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: engine.outputNode.inputFormat(forBus: 0).sampleRate, channels: 1)!
        let source = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let on = self.choice.file == nil
            let shape = self.followBreath ? 0.12 + 0.88 * self.level : 0.55
            let target = on ? self.volume * 0.36 * shape : 0
            for frame in 0..<Int(frameCount) {
                self.gain += (target - self.gain) * 0.0005
                self.brown = (self.brown + 0.02 * Double.random(in: -1...1)) / 1.02
                let sample = Float(self.brown * 3.5 * self.gain)
                for buffer in buffers { buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        waves = source
        engine.attach(player)
    }

    func choose(_ id: String) {
        let next = SoundChoice.named(id)
        guard next.id != choice.id || (next.file != nil && loadedFile != next.file) else { return }
        choice = next
        player.stop()
        if let file = next.file { load(file) }
        if engine.isRunning && next.file != nil { player.play() }
        updatePlayerVolume()
    }

    private func load(_ path: String) {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        loadedFile = path
    }

    private func updatePlayerVolume() {
        let shape = followBreath ? 0.35 + 0.65 * level : 1
        player.volume = Float(volume * shape)
    }

    func start() {
        try? engine.start()
        if choice.file != nil && !player.isPlaying { player.play() }
    }

    func stop() {
        player.pause()
        engine.pause()
    }
}
