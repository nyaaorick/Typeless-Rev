import Foundation
@preconcurrency import WhisperKit

/// The optional Whisper recognizer (large-v3-turbo through WhisperKit, on the Neural Engine).
///
/// Apple's recognizer always runs alongside it: Whisper only replaces the final text, and only
/// when it is installed, loaded, and answers in time. So everything here fails soft: `transcribe`
/// returns nil for any problem and the caller keeps Apple's text.
///
/// Like the polish model, it is downloaded, loaded, offloaded and uninstalled from the menu. The
/// first load after a download is slow (Core ML compiles the model for this Mac); later ones are quick.
actor WhisperEngine {
    static let shared = WhisperEngine()

    /// The folder in `argmaxinc/whisperkit-coreml`: OpenAI's large-v3-turbo, compressed by Argmax.
    static let variant = "openai_whisper-large-v3-v20240930_turbo_632MB"
    /// The tokenizer large-v3-turbo shares with large-v3, fetched from Hugging Face at install.
    private static let tokenizerVariant = ModelVariant.largev3
    /// The model (about 0.65 GB) and the tokenizer, with room to spare.
    private static let requiredFreeBytes: Int64 = 1_500_000_000
    /// Written last at install: the model folder's path inside `AppPaths.whisperDir`.
    private static let markerName = "MODEL"

    enum Install: Equatable {
        case notInstalled
        case downloading(fraction: Double)
        case installed(bytes: Int64)
        case failed(String)
    }

    enum Residency: Equatable {
        case offloaded, loading, loaded
    }

    /// For the menu. Main thread only; changes post `.whisperChanged`.
    nonisolated(unsafe) private(set) static var install = WhisperEngine.currentInstall() {
        didSet { if install != oldValue { NotificationCenter.default.post(name: .whisperChanged, object: nil) } }
    }
    nonisolated(unsafe) private(set) static var residency = Residency.offloaded {
        didSet { if residency != oldValue { NotificationCenter.default.post(name: .whisperChanged, object: nil) } }
    }

    private var kit: WhisperKit?
    private var loading: Task<WhisperKit, Error>?
    /// Bumped by `unload`, so a load it cancelled cannot report itself loaded afterwards.
    private var generation = 0
    private var installing: Task<Void, Never>?

    // MARK: - Install

    /// The installed model folder, or nil.
    nonisolated static var modelFolder: URL? {
        let marker = AppPaths.whisperDir.appendingPathComponent(markerName)
        guard let relative = try? String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !relative.isEmpty
        else { return nil }
        let folder = AppPaths.whisperDir.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    nonisolated static var isInstalled: Bool { modelFolder != nil }

    /// Installed and not offloaded: may be loaded now or on the next key press.
    nonisolated static var isAvailable: Bool { isInstalled && !VoiceSettings.whisperOffloaded }

    /// True when the next utterance can use Whisper. Main thread only.
    nonisolated static var isReady: Bool { residency == .loaded && isAvailable }

    /// Downloads into a staging folder and swaps it in last, so a half-done install is never seen.
    func startInstall() {
        guard installing == nil, !Self.isInstalled else { return }
        installing = Task {
            await runInstall()
            installing = nil
        }
    }

    func cancelInstall() {
        installing?.cancel()
    }

    /// Unloads and moves the model to the Trash, so removing it is undoable.
    func uninstall() {
        guard installing == nil else { return }
        unload()
        VoiceSettings.setWhisperOffloaded(false)
        try? FileManager.default.trashItem(at: AppPaths.whisperDir, resultingItemURL: nil)
        Self.publish(install: Self.currentInstall())
        Log.whisper.info("whisper model moved to the Trash")
    }

    private func runInstall() async {
        let fm = FileManager.default
        let finalDir = AppPaths.whisperDir
        let staging = finalDir.deletingLastPathComponent().appendingPathComponent("whisper.installing")
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: finalDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            let free = try finalDir.deletingLastPathComponent()
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage ?? 0
            guard free >= Self.requiredFreeBytes else { throw Failure.notEnoughSpace }
            try? fm.removeItem(at: staging)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)

            Self.publish(install: .downloading(fraction: 0))
            let started = Date()
            let folder = try await WhisperKit.download(variant: Self.variant, downloadBase: staging) { progress in
                Self.publish(install: .downloading(fraction: min(0.99, progress.fractionCompleted)))
            }
            try Task.checkCancellation()
            _ = try await ModelUtilities.loadTokenizer(for: Self.tokenizerVariant, tokenizerFolder: staging)
            try Task.checkCancellation()

            let relative = String(folder.standardizedFileURL.path.dropFirst(staging.standardizedFileURL.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            try relative.write(to: staging.appendingPathComponent(Self.markerName), atomically: true, encoding: .utf8)
            try? fm.removeItem(at: finalDir)
            try fm.moveItem(at: staging, to: finalDir)
            Log.whisper.info("whisper model installed in \(Date().timeIntervalSince(started), format: .fixed(precision: 0))s")
            Self.publish(install: Self.currentInstall())
            // Compile it for this Mac now, while nobody is waiting on it.
            load()
        } catch is CancellationError {
            Self.publish(install: .notInstalled)
        } catch {
            Log.whisper.error("whisper install failed: \(error.localizedDescription, privacy: .public)")
            Self.publish(install: .failed((error as? Failure)?.message ?? error.localizedDescription))
        }
    }

    nonisolated static func currentInstall() -> Install {
        guard let folder = modelFolder else { return .notInstalled }
        return .installed(bytes: size(of: folder))
    }

    private nonisolated static func size(of folder: URL) -> Int64 {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    enum Failure: Error {
        case notEnoughSpace, notInstalled

        var message: String {
            switch self {
            case .notEnoughSpace: "Not enough disk space (1.5 GB needed)."
            case .notInstalled: "The Whisper model is not installed."
            }
        }
    }

    // MARK: - Residency

    /// Starts loading in the background, so a later key press can use it.
    func warmUp() {
        guard Self.isAvailable, kit == nil else { return }
        _ = loadTask()
    }

    /// The menu's Load.
    func load() {
        VoiceSettings.setWhisperOffloaded(false)
        warmUp()
    }

    /// The menu's Offload: frees the memory, keeps the model on disk until Load.
    func offload() {
        VoiceSettings.setWhisperOffloaded(true)
        unload()
    }

    func unload() {
        generation += 1
        loading?.cancel()
        loading = nil
        let old = kit
        kit = nil
        Self.publish(residency: .offloaded)
        Task { await old?.unloadModels() }
    }

    private func loadTask() -> Task<WhisperKit, Error> {
        if let loading { return loading }
        let generation = generation
        Self.publish(residency: .loading)
        let task = Task<WhisperKit, Error> {
            guard let folder = Self.modelFolder else { throw Failure.notInstalled }
            let started = Date()
            do {
                let config = WhisperKitConfig(
                    modelFolder: folder.path, tokenizerFolder: AppPaths.whisperDir,
                    verbose: false, logLevel: .error, prewarm: false, load: true, download: false)
                let kit = try await WhisperKit(config)
                Log.whisper.info("whisper model loaded in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
                settle(generation: generation, kit: kit)
                return kit
            } catch {
                Log.whisper.error("whisper model failed to load: \(error.localizedDescription, privacy: .public)")
                settle(generation: generation, kit: nil)
                throw error
            }
        }
        loading = task
        return task
    }

    private func settle(generation: Int, kit: WhisperKit?) {
        guard generation == self.generation else { return }
        loading = nil
        self.kit = kit
        Self.publish(residency: kit == nil ? .offloaded : .loaded)
    }

    // MARK: - Transcription

    /// Whisper's text for 16 kHz mono `samples`, or nil when it is not loaded, fails, runs past
    /// `timeout`, or hears nothing. `prompt` primes it with the words to expect; `language` is an
    /// ISO code such as "en" or "zh", or nil to detect it.
    func transcribe(_ samples: [Float], prompt: String?, language: String?, timeout: Duration) async -> String? {
        guard let kit, !WhisperText.isSilent(samples) else { return nil }
        let started = Date()
        let seconds = Double(samples.count) / 16_000
        let text = await firstResult(timeout: timeout) {
            await Self.run(kit, samples: samples, prompt: prompt, language: language)
        }
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))
        let audio = String(format: "%.1f", seconds)
        if let text {
            Log.whisper.info("whisper: \(text.count) characters from \(audio, privacy: .public)s of audio in \(elapsed, privacy: .public)s")
        } else {
            Log.whisper.info("whisper: no text from \(audio, privacy: .public)s of audio (\(elapsed, privacy: .public)s)")
        }
        return text
    }

    private static func run(_ kit: WhisperKit, samples: [Float], prompt: String?, language: String?) async -> String? {
        var options = DecodingOptions(
            language: language, temperature: 0, temperatureFallbackCount: 2, usePrefillPrompt: true,
            detectLanguage: language == nil, skipSpecialTokens: true, withoutTimestamps: true)
        if let prompt, let tokenizer = kit.tokenizer {
            let tokens = tokenizer.encode(text: " " + prompt.trimmingCharacters(in: .whitespacesAndNewlines))
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.promptTokens = Array(tokens.suffix(WhisperText.maxPromptTokens))
        }
        do {
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
            return WhisperText.clean(results.map(\.text).joined(separator: " "))
        } catch {
            Log.whisper.error("whisper failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Publishing

    private nonisolated static func publish(install: Install) {
        DispatchQueue.main.async { Self.install = install }
    }

    private nonisolated static func publish(residency: Residency) {
        DispatchQueue.main.async { Self.residency = residency }
    }
}

extension Notification.Name {
    static let whisperChanged = Notification.Name("TypelessRevWhisperChanged")
}
