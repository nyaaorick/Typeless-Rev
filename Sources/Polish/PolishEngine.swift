import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Polishes a transcript with the local text-only Qwen model, in-process through MLX.
///
/// The model loads on the first press of the push-to-talk key (or from the menu's Load) and stays
/// in memory until the user offloads it from the menu. Offloaded, it stays on disk and is not
/// loaded again until the user picks Load. `polish` never throws: any failure, a missing or
/// offloaded model, or a timeout yields nil and the caller commits the raw transcript.
actor PolishEngine {
    static let shared = PolishEngine()

    enum Residency: Equatable {
        case offloaded, loading, loaded
    }

    /// Whether the weights are in memory, for the menu. Main thread only; changes post
    /// `.polishResidencyChanged`.
    nonisolated(unsafe) private(set) static var residency = Residency.offloaded {
        didSet {
            if residency != oldValue { NotificationCenter.default.post(name: .polishResidencyChanged, object: nil) }
        }
    }

    private var loading: Task<ModelContainer, Error>?
    /// Bumped by `offload`, so a load it cancelled cannot report itself loaded afterwards.
    private var generation = 0

    /// The model in memory (or loading), for the memory governor. Main thread only.
    nonisolated(unsafe) private(set) static var loadedModel: PolishModel?
    /// The model `loading` belongs to.
    private var loadingModel: PolishModel?

    /// True when the selected model has been installed (`scripts/prepare-model.sh`).
    nonisolated static var isInstalled: Bool { isInstalled(PolishModel.current) }

    nonisolated static func isInstalled(_ model: PolishModel) -> Bool {
        let fm = FileManager.default
        return ["config.json", "model.safetensors", "tokenizer.json"].allSatisfy {
            fm.fileExists(atPath: AppPaths.modelDir(for: model).appendingPathComponent($0).path)
        }
    }

    /// The model to polish with under the current memory tier: the selected one; the 4B in place
    /// of the 9B at tier 2; none at tier 3, or at tier 2 when the 4B is not installed.
    nonisolated static var effectiveModel: PolishModel? {
        switch MemoryGovernor.tier {
        case 3...: return nil
        case 2 where PolishModel.current == .qwen9b: return isInstalled(.qwen4b) ? .qwen4b : nil
        default: return PolishModel.current
        }
    }

    /// True when a model can be used now or loaded on demand: installed, not offloaded, and allowed
    /// by the memory tier.
    nonisolated static var isAvailable: Bool {
        guard let model = effectiveModel else { return false }
        return isInstalled(model) && !VoiceSettings.polishOffloaded
    }

    // MARK: - Public

    /// Starts loading in the background so the model is ready when the user lets go of the key.
    func warmUp() {
        guard Self.isAvailable else { return }
        _ = container()
    }

    /// The menu's Load: takes the model out of the offloaded state and loads it now.
    func load() {
        VoiceSettings.setPolishOffloaded(false)
        warmUp()
    }

    /// The menu's Offload: frees the memory and keeps the model on disk until the user loads it again.
    func offload() {
        VoiceSettings.setPolishOffloaded(true)
        unload()
    }

    /// Returns the polished text, or nil if the model is missing, too slow, or its answer is not trusted.
    /// The timeout covers loading too; a load that outlives it carries on for the next call.
    /// `context` is the text around the cursor, read by the model and never part of its answer.
    func polish(_ transcript: String, context: DictationContext? = nil, timeout: Duration) async -> String? {
        await polishWithReply(transcript, context: context, timeout: timeout).accepted
    }

    /// `polish`, plus the model's raw reply, for the log and for `--polish-text`.
    func polishWithReply(
        _ transcript: String, context: DictationContext? = nil, timeout: Duration
    ) async -> (reply: String?, accepted: String?) {
        guard Self.isAvailable, !transcript.isEmpty else { return (nil, nil) }
        let started = Date()
        let reply = await firstResult(timeout: timeout) { [self] in
            try? await generate(transcript, context: context)
        }
        let seconds = String(format: "%.2f", Date().timeIntervalSince(started))
        guard let reply else {
            Log.polish.info("polish: no reply within the timeout (\(seconds, privacy: .public)s, \(transcript.count) characters in)")
            return (nil, nil)
        }
        let accepted = PolishPrompt.accept(reply, for: transcript, context: context)
        Log.polish.info(
            "polish: reply \(accepted == nil ? "rejected" : "accepted", privacy: .public) in \(seconds, privacy: .public)s, \(transcript.count) characters in, \(reply.count) out")
        return (reply, accepted)
    }

    /// Selects another model. Only one is ever in memory: the current one is unloaded first, and
    /// the new one loads at the next key press or the menu's Load.
    func switchModel(to model: PolishModel) {
        guard model != PolishModel.current else { return }
        unload()
        VoiceSettings.setPolishModel(model)
        Log.polish.info("polish model switched to \(model.rawValue, privacy: .public)")
    }

    /// Freed buffers MLX may keep for reuse. Without a cap it parks up to the whole model's worth;
    /// a short reply needs little, so everything above this goes back to the system at once.
    private static let cacheLimit = 256 << 20

    /// Releases the model and its GPU cache.
    func unload() {
        generation += 1
        loading?.cancel()
        loading = nil
        loadingModel = nil
        releaseCache()
        publish(.offloaded, model: nil)
        Log.polish.info("polish model unloaded")
    }

    /// The weights are freed a moment after the last reference goes, and freed buffers wait in
    /// MLX's cache until it is cleared: clearing only once, right away, left all 2.4 GB parked there.
    /// When the last reference goes is not known: a request that timed out keeps generating for a
    /// moment and holds the model, and its weights reached the cache 0.75 s after the unload, past a
    /// single clear at 0.5 s (both measured by `--selftest-polish`). So keep clearing for as long as
    /// the longest request can run, unless the model is loaded again. An empty cache clears for free.
    private func releaseCache() {
        MLX.Memory.clearCache()
        Task {
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                guard loading == nil else { return }
                MLX.Memory.clearCache()
            }
        }
    }

    /// In call order: the main queue is first in, first out.
    private nonisolated func publish(_ residency: Residency, model: PolishModel?) {
        DispatchQueue.main.async {
            Self.loadedModel = model
            Self.residency = residency
        }
    }

    // MARK: - Loading and generation

    private func container() -> Task<ModelContainer, Error> {
        let model = Self.effectiveModel ?? PolishModel.current
        if let loading, loadingModel == model { return loading }
        // Another model is in memory (the tier changed): only one is ever loaded.
        if loading != nil { unload() }
        guard MemoryGovernor.canLoad(bytes: model.memoryBytes) else {
            Log.polish.info("polish model \(model.rawValue, privacy: .public) not loaded: memory is low")
            return Task { throw PolishLoadError.lowMemory }
        }
        let directory = AppPaths.modelDir(for: model)
        let generation = generation
        MLX.Memory.cacheLimit = Self.cacheLimit
        loadingModel = model
        publish(.loading, model: model)
        let task = Task {
            let started = Date()
            PolishCrashGuard.shared.begin()
            defer { PolishCrashGuard.shared.end() }
            do {
                let container = try await loadModelContainer(from: directory, using: TransformersTokenizerLoader())
                Log.polish.info("polish model loaded in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
                loaded(generation: generation, succeeded: true)
                return container
            } catch {
                Log.polish.error("polish model failed to load: \(error.localizedDescription, privacy: .public)")
                loaded(generation: generation, succeeded: false)
                throw error
            }
        }
        loading = task
        return task
    }

    private func generate(_ transcript: String, context: DictationContext?) async throws -> String {
        let container = try await container().value
        PolishCrashGuard.shared.begin()
        var finished = false
        defer { PolishCrashGuard.shared.end(succeeded: finished) }
        // A fresh session per request: no history, no cache carried over from another field.
        let session = ChatSession(
            container,
            instructions: PolishPrompt.instructions(style: context?.style ?? .plain, context: context),
            generateParameters: GenerateParameters(maxTokens: PolishPrompt.maxTokens(for: transcript), temperature: 0),
            additionalContext: ["enable_thinking": false])
        let reply = try await session.respond(to: PolishPrompt.userMessage(for: transcript))
        finished = true
        return reply
    }

    /// Settles the state once a load ends, unless it was offloaded meanwhile. A failed load is
    /// forgotten, so the next use tries again.
    private func loaded(generation: Int, succeeded: Bool) {
        guard generation == self.generation else { return }
        if !succeeded {
            loading = nil
            loadingModel = nil
        }
        publish(succeeded ? .loaded : .offloaded, model: succeeded ? loadingModel : nil)
    }
}

enum PolishLoadError: Error {
    case lowMemory
}

extension Notification.Name {
    static let polishResidencyChanged = Notification.Name("TypelessRevPolishResidencyChanged")
}

/// Runs `work` and returns its result, or nil once `timeout` passes. Returns at the
/// timeout even if `work` is slow to notice it was cancelled.
func firstResult(timeout: Duration, _ work: @escaping @Sendable () async -> String?) async -> String? {
    await withCheckedContinuation { continuation in
        let gate = OnceGate()
        let job = Task {
            let result = await work()
            if gate.claim() { continuation.resume(returning: result) }
        }
        Task {
            try? await Task.sleep(for: timeout)
            job.cancel()
            if gate.claim() { continuation.resume(returning: nil) }
        }
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// True for the first caller only.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
