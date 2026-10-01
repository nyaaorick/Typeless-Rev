import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Polishes a transcript with the local text-only Qwen model, in-process through MLX.
///
/// The model loads lazily, stays warm while it is in use, and is released after an idle
/// period. `polish` never throws: any failure, a missing model, or a timeout yields nil
/// and the caller commits the raw transcript.
actor PolishEngine {
    static let shared = PolishEngine()

    /// Memory is given back this long after the last use.
    private let idleUnload: Duration = .seconds(300)

    private var loading: Task<ModelContainer, Error>?
    private var idleTask: Task<Void, Never>?

    /// True when the text-only model has been installed (`scripts/prepare-model.sh`).
    nonisolated static var isInstalled: Bool {
        let fm = FileManager.default
        return ["config.json", "model.safetensors", "tokenizer.json"].allSatisfy {
            fm.fileExists(atPath: AppPaths.modelDir.appendingPathComponent($0).path)
        }
    }

    // MARK: - Public

    /// Starts loading in the background so the model is ready when the user lets go of the key.
    func warmUp() {
        guard Self.isInstalled else { return }
        _ = container()
        scheduleUnload()
    }

    /// Returns the polished text, or nil if the model is missing, too slow, or its answer is not trusted.
    /// The timeout covers loading too; a load that outlives it carries on for the next call.
    func polish(_ transcript: String, timeout: Duration) async -> String? {
        guard Self.isInstalled, !transcript.isEmpty else { return nil }
        let reply = await firstResult(timeout: timeout) { [self] in
            try? await generate(transcript)
        }
        scheduleUnload()
        guard let reply else { return nil }
        return PolishPrompt.accept(reply, for: transcript)
    }

    /// Releases the model and its GPU cache.
    func unload() {
        idleTask?.cancel()
        idleTask = nil
        loading?.cancel()
        loading = nil
        releaseCache()
        Log.polish.info("polish model unloaded")
    }

    /// The weights are freed a moment after the last reference goes, and freed buffers wait in
    /// MLX's cache until it is cleared: clearing only once, right away, left all 2.4 GB parked there
    /// (measured by `--selftest-polish`). So clear again after they have gone.
    private func releaseCache() {
        MLX.Memory.clearCache()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            MLX.Memory.clearCache()
        }
    }

    // MARK: - Loading and generation

    private func container() -> Task<ModelContainer, Error> {
        if let loading { return loading }
        let directory = AppPaths.modelDir
        let task = Task {
            let started = Date()
            PolishCrashGuard.shared.begin()
            defer { PolishCrashGuard.shared.end() }
            let container = try await loadModelContainer(from: directory, using: TransformersTokenizerLoader())
            Log.polish.info("polish model loaded in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
            return container
        }
        loading = task
        return task
    }

    private func generate(_ transcript: String) async throws -> String {
        let container = try await container().value
        PolishCrashGuard.shared.begin()
        var finished = false
        defer { PolishCrashGuard.shared.end(succeeded: finished) }
        // A fresh session per request: no history, no cache carried over from another field.
        let session = ChatSession(
            container,
            instructions: PolishPrompt.system,
            generateParameters: GenerateParameters(maxTokens: PolishPrompt.maxTokens(for: transcript), temperature: 0),
            additionalContext: ["enable_thinking": false])
        let reply = try await session.respond(to: PolishPrompt.userMessage(for: transcript))
        finished = true
        return reply
    }

    private func scheduleUnload() {
        idleTask?.cancel()
        let delay = idleUnload
        idleTask = Task { [self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            unload()
        }
    }
}

/// Runs `work` and returns its result, or nil once `timeout` passes. Returns at the
/// timeout even if `work` is slow to notice it was cancelled.
private func firstResult(timeout: Duration, _ work: @escaping @Sendable () async -> String?) async -> String? {
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
