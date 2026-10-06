import CryptoKit
import Foundation

/// Installs the selected polish model (`PolishModel.current`): downloads the pinned checkpoint from
/// Hugging Face, checks it against the pinned SHA-256, and writes a text-only copy without the
/// vision tower where the download has one.
///
/// Everything happens in a staging directory next to the final one and is swapped in last,
/// so `PolishEngine.isInstalled` never sees a half-installed model. State is read and the
/// change handler runs on the main thread.
final class ModelInstaller {
    static let shared = ModelInstaller()

    enum State: Equatable {
        case notInstalled
        case downloading(fraction: Double)
        /// Verifying the download and writing the text-only copy.
        case preparing
        case installed(bytes: Int64)
        case failed(String)
    }

    private(set) var state: State = ModelInstaller.currentState()
    var onChange: (() -> Void)?

    private var task: Task<Void, Never>?
    private var download: FileDownload?

    var isRunning: Bool { task != nil }

    // MARK: - Control

    func install() {
        guard task == nil, !PolishEngine.isInstalled else { return }
        let model = PolishModel.current
        task = Task { [self] in
            await run(model)
            await MainActor.run {
                task = nil
                download = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        download?.cancel()
    }

    /// Re-reads the state after the selected model changed.
    func refresh() {
        guard task == nil else { return }
        set(Self.currentState())
    }

    /// Moves the model to the Trash, so removing it is undoable.
    func remove() {
        guard task == nil else { return }
        Task { await PolishEngine.shared.unload() }
        // A model installed later starts out like a fresh one, loading on first use.
        VoiceSettings.setPolishOffloaded(false)
        try? FileManager.default.trashItem(at: AppPaths.modelDir, resultingItemURL: nil)
        set(Self.currentState())
    }

    static func currentState() -> State {
        guard PolishEngine.isInstalled else { return .notInstalled }
        let size = (try? AppPaths.modelDir.appendingPathComponent(PolishModel.current.weights.name)
            .resourceValues(forKeys: [.fileSizeKey]))?
            .fileSize
        return .installed(bytes: Int64(size ?? 0))
    }

    // MARK: - Install

    private func run(_ model: PolishModel) async {
        let fm = FileManager.default
        let finalDir = AppPaths.modelDir(for: model)
        let staging = finalDir.deletingLastPathComponent().appendingPathComponent("\(model.folderName).installing")
        defer { try? fm.removeItem(at: staging) }
        do {
            try Self.requireFreeSpace(model.requiredFreeBytes, near: finalDir.deletingLastPathComponent())
            try? fm.removeItem(at: staging)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)

            set(.downloading(fraction: 0))
            for file in model.files {
                let data = try await Self.fetch(file.name, of: model)
                if let expected = file.sha256, SHA256.hash(data: data).hex != expected { throw Failure.checksum(file.name) }
                let out = staging.appendingPathComponent(file.name)
                try (file.name == "config.json" ? try Self.withoutVision(data) : data).write(to: out)
            }

            let downloaded = staging.appendingPathComponent("download.partial")
            let transfer = FileDownload { [weak self] fraction in self?.set(.downloading(fraction: fraction)) }
            await MainActor.run { download = transfer }
            let weights = model.weights
            try await transfer.run(url: Self.url(for: weights.name, of: model), to: downloaded)

            set(.preparing)
            let target = staging.appendingPathComponent(weights.name)
            try await Task.detached {
                guard try Self.sha256(of: downloaded) == weights.sha256 else { throw Failure.checksum(weights.name) }
                if model.hasVision {
                    let result = try SafetensorsFilter.copy(from: downloaded, to: target, dropping: Self.isVision)
                    try FileManager.default.removeItem(at: downloaded)
                    Log.polish.info("installed \(result.kept) tensors, dropped \(result.dropped) vision tensors")
                } else {
                    // Already text-only: use the download as it is, no second copy.
                    try FileManager.default.moveItem(at: downloaded, to: target)
                }
            }.value
            try "\(model.repo)@\(model.revision)\n".write(
                to: staging.appendingPathComponent("REVISION"), atomically: true, encoding: .utf8)

            try Task.checkCancellation()
            try? fm.removeItem(at: finalDir)
            try fm.moveItem(at: staging, to: finalDir)
            set(Self.currentState())
        } catch is CancellationError {
            set(.notInstalled)
        } catch let error as URLError where error.code == .cancelled {
            set(.notInstalled)
        } catch {
            Log.polish.error("model install failed: \(error.localizedDescription, privacy: .public)")
            set(.failed((error as? Failure)?.message ?? error.localizedDescription))
        }
    }

    private func set(_ new: State) {
        DispatchQueue.main.async {
            guard self.state != new else { return }
            self.state = new
            self.onChange?()
        }
    }

    // MARK: - Helpers

    enum Failure: Error {
        case notEnoughSpace
        case checksum(String)
        case http(Int)

        var message: String {
            switch self {
            case .notEnoughSpace:
                let gigabytes = Double(PolishModel.current.requiredFreeBytes) / 1e9
                return String(format: "Not enough free disk space (%.1f GB needed while installing).", gigabytes)
            case .checksum(let file): return "The downloaded \(file) is corrupt. Try again."
            case .http(let code): return "The download server answered \(code)."
            }
        }
    }

    /// Tensors that belong to the vision encoder, which polishing never uses.
    static func isVision(_ name: String) -> Bool {
        ["vision_tower", "model.visual", "visual."].contains { name.hasPrefix($0) }
    }

    private static func url(for file: String, of model: PolishModel) -> URL {
        URL(string: "https://huggingface.co/\(model.repo)/resolve/\(model.revision)/\(file)")!
    }

    private static func fetch(_ file: String, of model: PolishModel) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url(for: file, of: model))
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw Failure.http(status)
        }
        return data
    }

    /// Drops the vision encoder's settings: the text-only copy has no such model to configure.
    private static func withoutVision(_ config: Data) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: config) as? [String: Any] else { return config }
        json.removeValue(forKey: "vision_config")
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }

    private static func requireFreeSpace(_ requiredFreeBytes: Int64, near directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let free = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage ?? 0
        if free < requiredFreeBytes { throw Failure.notEnoughSpace }
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 16 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().hex
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

/// One file download with progress. The system writes to a temporary file; it is moved to
/// `destination` before the delegate callback returns, as URLSession requires.
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var failure: Error?
    private var task: URLSessionDownloadTask?
    private var lastReported = -1.0

    init(progress: @escaping (Double) -> Void) {
        self.progress = progress
    }

    func run(url: URL, to destination: URL) async throws {
        self.destination = destination
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                let task = session.downloadTask(with: url)
                self.task = task
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
        totalBytesWritten written: Int64, totalBytesExpectedToWrite expected: Int64
    ) {
        guard expected > 0 else { return }
        let fraction = Double(written) / Double(expected)
        // 0.5% steps are plenty for a menu.
        guard fraction - lastReported >= 0.005 || fraction >= 1 else { return }
        lastReported = fraction
        progress(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            failure = ModelInstaller.Failure.http(status)
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination!)
            try FileManager.default.moveItem(at: location, to: destination!)
        } catch {
            failure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if let error = error ?? failure {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
