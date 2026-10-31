import AVFoundation

/// Soft brown noise, like distant waves, that swells as you breathe in and fades as you breathe out.
final class Sound {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    /// 0...1, set from the main thread; read by the audio thread. A torn read only costs one quiet sample.
    var level: Double = 0
    private var gain: Double = 0
    private var brown: Double = 0

    var isRunning: Bool { engine.isRunning }

    func start() {
        if node == nil {
            let format = engine.outputNode.inputFormat(forBus: 0)
            let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
            let source = AVAudioSourceNode(format: mono) { [unowned self] _, _, frameCount, audioBufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                let target = 0.04 + 0.32 * self.level
                for frame in 0..<Int(frameCount) {
                    self.gain += (target - self.gain) * 0.0005
                    let white = Double.random(in: -1...1)
                    self.brown = (self.brown + 0.02 * white) / 1.02
                    let sample = Float(self.brown * 3.5 * self.gain)
                    for buffer in buffers {
                        buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                    }
                }
                return noErr
            }
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: mono)
            node = source
        }
        try? engine.start()
    }

    func stop() { engine.pause() }
}
