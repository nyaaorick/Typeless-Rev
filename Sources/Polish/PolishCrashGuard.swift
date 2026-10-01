import Foundation

/// Notices when the previous run died inside the polish model, and stops polishing if it keeps
/// happening (see `CrashCounter`).
///
/// A marker file exists exactly while the model is loading or generating, so a run that dies in
/// there leaves it behind. The file is written before the risky call, which is the only way to
/// see a crash from the next launch.
final class PolishCrashGuard: @unchecked Sendable {
    static let shared = PolishCrashGuard()

    private let marker: URL
    private let lock = NSLock()
    private var active = 0

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Typeless-Rev")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        marker = support.appendingPathComponent("polish-active")
    }

    /// Call once at launch. Returns true if polishing was just switched off.
    @discardableResult
    func recoverFromPreviousRun() -> Bool {
        guard FileManager.default.fileExists(atPath: marker.path) else { return false }
        try? FileManager.default.removeItem(at: marker)
        var counter = CrashCounter(consecutive: VoiceSettings.polishCrashes)
        let disable = counter.previousRunDied()
        VoiceSettings.setPolishCrashes(counter.consecutive)
        Log.polish.error("the previous run died while polishing (\(counter.consecutive) in a row)")
        if disable {
            VoiceSettings.setPolishEnabled(false)
            VoiceSettings.setPolishDisabledByCrash(true)
            Log.polish.error("polishing is switched off after repeated crashes")
        }
        return disable
    }

    /// Wrap the model load and each generation in `begin()` / `end(succeeded:)`.
    func begin() {
        lock.lock()
        defer { lock.unlock() }
        active += 1
        if active == 1 { FileManager.default.createFile(atPath: marker.path, contents: Data()) }
    }

    /// `succeeded` is true for a finished generation (not for a load), which clears the crash count.
    func end(succeeded: Bool = false) {
        lock.lock()
        active = max(0, active - 1)
        if active == 0 { try? FileManager.default.removeItem(at: marker) }
        lock.unlock()
        if succeeded, VoiceSettings.polishCrashes != 0 { VoiceSettings.setPolishCrashes(0) }
    }
}
