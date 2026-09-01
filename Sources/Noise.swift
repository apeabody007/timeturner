import AVFoundation

// Brown noise, generated sample by sample: integrated white noise with a
// slight leak back toward zero, which gives the classic low, even rumble
// that masks a room without the hiss of white noise. The gain chases
// `target` slowly, so the sound fades in and out instead of clicking, and
// the app sets the target from the hour: full while the work sand runs,
// a whisper during breaks.
final class BrownNoise {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode!
    var target: Float = 0

    init() {
        var brown: Float = 0
        var level: Float = 0
        var seed: UInt32 = 22222 // xorshift; Float.random is too slow to call 44k times a second
        node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let target = self?.target ?? 0
            for frame in 0..<Int(frameCount) {
                seed ^= seed << 13
                seed ^= seed >> 17
                seed ^= seed << 5
                let white = Float(seed) / Float(UInt32.max) * 2 - 1
                brown = (brown + 0.02 * white) / 1.02
                level += (target - level) * 0.00005
                let sample = brown * 3.5 * 0.12 * level
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(node)
        let format = AVAudioFormat(standardFormatWithSampleRate:
            engine.outputNode.outputFormat(forBus: 0).sampleRate, channels: 1)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func start() { try? engine.start() }
    func stop() { engine.pause() }
}
