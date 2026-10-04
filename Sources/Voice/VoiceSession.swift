import AVFoundation
import Speech

/// What a session listens for.
enum Recognition {
    /// One language, chosen from the menu.
    case fixed(Locale)
    /// English and Mandarin at once on the same audio; whichever fits the speech wins.
    /// `hint` (the input mode's language) only breaks a tie.
    case auto(hint: SpeechLanguage?)

    static let englishLocale = Locale(identifier: "en-US")
    static let chineseLocale = Locale(identifier: "zh-CN")

    /// The locales whose on-device speech models this needs. In `.auto` the order is
    /// English, then Chinese.
    var locales: [Locale] {
        switch self {
        case .fixed(let locale): return [locale]
        case .auto: return [Recognition.englishLocale, Recognition.chineseLocale]
        }
    }
}

/// One push-to-talk utterance: audio in, live transcript out.
///
/// A new session is made for every utterance and never reused, so a callback can
/// only ever belong to the utterance that produced it. Cancelling is final: after
/// `cancel()` no callback fires, which is how the input controller guarantees a
/// late result never lands in the wrong field.
///
/// All public methods and all callbacks run on the main thread.
final class VoiceSession {
    private enum Phase {
        case idle, running, finishing, done
    }

    private struct Pipeline {
        let analyzer: SpeechAnalyzer
        let input: AsyncStream<AnalyzerInput>.Continuation
        let results: [Task<Void, Never>]
    }

    /// The transcript so far (finalized text plus the current volatile guess).
    var onText: ((String) -> Void)?
    /// The final transcript, after `finish()`. Fires at most once; may be empty.
    var onFinish: ((String) -> Void)?
    var onFailure: ((VoiceError) -> Void)?
    /// Microphone level, 0...1, a dozen times a second while listening.
    var onLevel: ((Float) -> Void)?

    private let recognition: Recognition
    private let feed: AudioFeed
    /// How long to wait for the recognizer to finalize before using what we have.
    private let finalizeTimeout: Duration

    private var phase = Phase.idle
    /// One per locale in `recognition.locales`; each hears the same audio.
    private var tracks: [RecognitionTrack]
    /// The language the transcript was taken from, once an auto-detecting utterance is delivered.
    /// Nil for a fixed locale.
    private(set) var detectedLanguage: SpeechLanguage?
    /// Mean confidence of each recognizer's final text, in `recognition.locales` order. For diagnostics.
    var confidences: [Double?] { tracks.map(\.confidence) }
    /// Set when the key is released before setup has finished; setup then finalizes on completion.
    private var finishRequested = false
    private var pipeline: Pipeline?
    private var setupTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    /// For the summary logged at the end: loudest meter reading and number of transcript updates.
    private var peakLevel: Float = 0
    private var updates = 0
    private var setupFinished = false
    private let startedAt = ContinuousClock.now

    init(recognition: Recognition, feed: AudioFeed = MicrophoneFeed(), finalizeTimeout: Duration = .seconds(3)) {
        self.recognition = recognition
        self.tracks = Array(repeating: RecognitionTrack(), count: recognition.locales.count)
        self.feed = feed
        self.finalizeTimeout = finalizeTimeout
    }

    convenience init(locale: Locale, feed: AudioFeed = MicrophoneFeed(), finalizeTimeout: Duration = .seconds(3)) {
        self.init(recognition: .fixed(locale), feed: feed, finalizeTimeout: finalizeTimeout)
    }

    static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults],
            attributeOptions: [.transcriptionConfidence])
    }

    /// Sum of confidence times characters over the runs of a result, and the characters covered.
    private static func confidence(of text: AttributedString) -> (sum: Double, weight: Int)? {
        var sum = 0.0
        var weight = 0
        for run in text.runs {
            guard let confidence = run.transcriptionConfidence else { continue }
            let length = text[run.range].characters.count
            sum += confidence * Double(length)
            weight += length
        }
        return weight > 0 ? (sum, weight) : nil
    }

    // MARK: - Control

    func start() {
        guard phase == .idle else { return }
        phase = .running
        feed.onLevel = { level in
            DispatchQueue.main.async { self.deliverLevel(level) }
        }
        setupTask = Task { await self.setUp() }
    }

    /// The key was released: stop listening and deliver the final transcript.
    ///
    /// Released before setup finished, a live microphone has not started, so there is nothing to
    /// wait for: an empty result is delivered at once. (Finalizing an analyzer that got no audio
    /// hangs until `finalizeTimeout`, which kept the HUD up for three seconds after a quick tap.)
    func finish() {
        guard phase == .running else { return }
        finishRequested = true
        if pipeline != nil {
            beginFinalizing()
        } else if feed.isLive {
            phase = .finishing
            deliver()
        }
    }

    /// Abandons the utterance without delivering anything.
    func cancel() {
        guard phase != .done else { return }
        phase = .done
        teardown()
    }

    // MARK: - Setup (off the main thread)

    private func setUp() async {
        var analyzer: SpeechAnalyzer?
        var input: AsyncStream<AnalyzerInput>.Continuation?
        var results: [Task<Void, Never>] = []
        do {
            var transcribers: [SpeechTranscriber] = []
            for locale in recognition.locales {
                guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                    throw VoiceError.unsupportedLocale(locale.identifier)
                }
                let transcriber = Self.makeTranscriber(locale: resolved)
                guard await VoiceAssets.isInstalled(transcriber, locale: resolved) else {
                    throw VoiceError.assetsMissing(resolved.identifier)
                }
                transcribers.append(transcriber)
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: transcribers) else {
                throw VoiceError.noAudioFormat
            }

            let newAnalyzer = SpeechAnalyzer(modules: transcribers)
            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            analyzer = newAnalyzer
            input = continuation
            for (index, transcriber) in transcribers.enumerated() {
                results.append(
                    Task {
                        do {
                            for try await result in transcriber.results {
                                let text = String(result.text.characters)
                                let isFinal = result.isFinal
                                let confidence = Self.confidence(of: result.text)
                                await MainActor.run {
                                    self.apply(text, isFinal: isFinal, confidence: confidence, track: index)
                                }
                            }
                        } catch {
                            let message = error.localizedDescription
                            await MainActor.run { self.fail(.engine(message)) }
                        }
                    })
            }

            try await newAnalyzer.start(inputSequence: stream)
            try Task.checkCancellation()
            try await feed.start(target: format) { buffer in
                continuation.yield(AnalyzerInput(buffer: buffer))
            }

            let pipeline = Pipeline(analyzer: newAnalyzer, input: continuation, results: results)
            await MainActor.run { self.ready(pipeline) }
        } catch {
            feed.stop()
            input?.finish()
            results.forEach { $0.cancel() }
            await analyzer?.cancelAndFinishNow()
            let failure = (error as? VoiceError) ?? .engine(error.localizedDescription)
            await MainActor.run { self.fail(failure) }
        }
    }

    // MARK: - Main-thread transitions

    private func ready(_ pipeline: Pipeline) {
        guard phase != .done else {
            feed.stop()
            pipeline.input.finish()
            pipeline.results.forEach { $0.cancel() }
            Task { await pipeline.analyzer.cancelAndFinishNow() }
            return
        }
        self.pipeline = pipeline
        setupFinished = true
        if finishRequested { beginFinalizing() }
    }

    private func deliverLevel(_ level: Float) {
        guard phase == .running else { return }
        peakLevel = max(peakLevel, level)
        onLevel?(level)
    }

    private func apply(_ text: String, isFinal: Bool, confidence: (sum: Double, weight: Int)?, track: Int) {
        guard phase == .running || phase == .finishing else { return }
        tracks[track].apply(text, isFinal: isFinal, confidence: confidence)
        updates += 1
        onText?(tracks[leadingTrack].text)
    }

    /// The track whose text is shown while the user speaks.
    private var leadingTrack: Int {
        guard case .auto = recognition else { return 0 }
        return LanguagePicker.liveLeader(english: tracks[0], chinese: tracks[1]) == .english ? 0 : 1
    }

    /// The track whose text is committed.
    private func chooseWinner() -> Int {
        guard case .auto(let hint) = recognition else { return 0 }
        let language = LanguagePicker.winner(english: tracks[0], chinese: tracks[1], hint: hint)
        detectedLanguage = language
        return language == .english ? 0 : 1
    }

    private func beginFinalizing() {
        guard let pipeline, phase == .running else { return }
        phase = .finishing
        feed.stop()
        pipeline.input.finish()

        // Nothing recognized yet: do not hold the HUD up for the full timeout. A real word shows
        // a partial result within about 300 ms, so this only shortens a silent press.
        let heardNothing = feed.isLive && tracks.allSatisfy { $0.text.isEmpty }
        let timeout = heardNothing ? min(finalizeTimeout, .seconds(1)) : finalizeTimeout
        timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            await MainActor.run { self.deliver() }
        }
        Task {
            do {
                try await pipeline.analyzer.finalizeAndFinishThroughEndOfInput()
                for task in pipeline.results { await task.value }
            } catch {
                Log.ime.error("speech finalize failed: \(error.localizedDescription, privacy: .public)")
            }
            await MainActor.run { self.deliver() }
        }
    }

    private func deliver() {
        guard phase == .finishing else { return }
        phase = .done
        teardown()
        let text = tracks[chooseWinner()].text.trimmingCharacters(in: .whitespacesAndNewlines)
        logSummary("finished", characters: text.count)
        onFinish?(text)
    }

    private func logSummary(_ outcome: String, characters: Int) {
        let elapsed = startedAt.duration(to: .now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        Log.ime.info(
            "voice summary: \(outcome, privacy: .public), setup \(self.setupFinished ? "done" : "not done", privacy: .public), peak level \(String(format: "%.2f", self.peakLevel), privacy: .public), \(self.updates) updates, \(characters) characters, \(String(format: "%.2f", seconds), privacy: .public)s")
    }

    private func fail(_ error: VoiceError) {
        guard phase != .done else { return }
        phase = .done
        teardown()
        logSummary("failed: \(error.message)", characters: 0)
        onFailure?(error)
    }

    private func teardown() {
        feed.onLevel = nil
        feed.stop()
        setupTask?.cancel()
        timeoutTask?.cancel()
        if let pipeline {
            pipeline.input.finish()
            pipeline.results.forEach { $0.cancel() }
            Task { await pipeline.analyzer.cancelAndFinishNow() }
        }
        pipeline = nil
    }
}
