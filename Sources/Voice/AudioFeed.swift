import AVFoundation

/// Where a `VoiceSession` gets its audio. The analyzer pipeline does not care whether
/// it is the microphone or, in the self-test, a file.
protocol AudioFeed: AnyObject {
    /// Meter position (0...1) of the audio being captured. Called on the audio thread.
    var onLevel: ((Float) -> Void)? { get set }
    /// True when audio only exists once capture has started and while the user speaks (the
    /// microphone); false when it is all there up front (a file).
    var isLive: Bool { get }

    /// Starts delivering buffers in `target` format. Returns once capture is running
    /// (the microphone) or everything has been delivered (a file).
    func start(target: AVAudioFormat, yield: @escaping (AVAudioPCMBuffer) -> Void) async throws
    func stop()
}

/// Converts buffers to the analyzer's preferred format.
final class BufferConverter {
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?

    init(target: AVAudioFormat) {
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}

/// A 16 kHz mono copy of what the microphone hears, for Whisper. Appended on the audio thread.
final class SampleRecorder: @unchecked Sendable {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private let lock = NSLock()
    private var samples: [Float] = []
    private let converter = BufferConverter(target: SampleRecorder.format)

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = converter.convert(buffer), let data = converted.floatChannelData?[0] else { return }
        let chunk = UnsafeBufferPointer(start: data, count: Int(converted.frameLength))
        lock.withLock { samples.append(contentsOf: chunk) }
    }

    var recorded: [Float] { lock.withLock { samples } }
}

/// Live microphone capture through `AVAudioEngine`.
final class MicrophoneFeed: AudioFeed {
    var onLevel: ((Float) -> Void)?
    let isLive = true
    /// Also gets every buffer, when set before `start`.
    var recorder: SampleRecorder?

    private let engine = AVAudioEngine()
    private var tapInstalled = false

    func start(target: AVAudioFormat, yield: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        try await Self.requireAccess()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.noInputDevice }

        let converter = BufferConverter(target: target)
        let recorder = recorder
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            recorder?.append(buffer)
            if let channel = buffer.floatChannelData?[0] {
                let rms = AudioLevel.rms(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                self?.onLevel?(AudioLevel.meter(rms: rms))
            }
            if let converted = converter.convert(buffer) { yield(converted) }
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw VoiceError.engine(error.localizedDescription)
        }
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
    }

    private static func requireAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            // The TCC prompt attributes to this bundle via NSMicrophoneUsageDescription.
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw VoiceError.microphoneDenied }
        default:
            throw VoiceError.microphoneDenied
        }
    }
}

/// Feeds an audio file through the pipeline as fast as the analyzer accepts it.
/// Used by `--selftest-speech`; it needs no microphone permission.
final class FileFeed: AudioFeed {
    var onLevel: ((Float) -> Void)?
    let isLive = false

    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func start(target: AVAudioFormat, yield: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        let file = try AVAudioFile(forReading: url)
        let converter = BufferConverter(target: target)
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { break }
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            if let converted = converter.convert(buffer) { yield(converted) }
        }
    }

    func stop() {}
}
