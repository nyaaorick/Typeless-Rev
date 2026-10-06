import Foundation

/// Steps the voice models down when macOS reports memory pressure, and lets them back up once it
/// has passed (`MemoryTierTracker` has the tiers). Under pressure the system does not unload
/// anything of ours: it compresses and swaps the weights, and a swapped model answers too slowly
/// to be any use. So the governor unloads them itself.
///
/// The tier lives only in memory: the user's choices (Whisper, the 9B, their offload state) never
/// change. Engines read `tier` before loading and fall back to the next model down. Main thread.
final class MemoryGovernor {
    static let shared = MemoryGovernor()

    /// What the engines go by: 0 when the setting is off. Read from any thread.
    nonisolated(unsafe) private(set) static var tier = 0

    private var tracker = MemoryTierTracker()
    private var source: DispatchSourceMemoryPressure?
    private var timer: Timer?

    func start() {
        guard source == nil else { return }
        tracker.update(Self.currentPressure(), at: Self.now)
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let event = source?.data else { return }
            let pressure: MemoryPressure =
                event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
            Log.app.info("memory pressure: \(pressure.rawValue, privacy: .public)")
            tracker.update(pressure, at: Self.now)
            apply()
        }
        source.resume()
        self.source = source
        // The tracker's steps are time-based (a lasting warning, a lasting calm).
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            tracker.tick(at: Self.now)
            apply()
        }
        apply()
    }

    /// The menu toggle changed.
    func settingChanged() {
        apply()
    }

    /// True when `bytes` more can be loaded without squeezing the system (`MemoryBudget`).
    static func canLoad(bytes: Int64) -> Bool {
        guard VoiceSettings.autoDowngrade else { return true }
        return MemoryBudget.canLoad(
            bytes: bytes, freePercent: sysctlInt("kern.memorystatus_level") ?? 100,
            totalBytes: Int64(ProcessInfo.processInfo.physicalMemory))
    }

    private func apply() {
        var target = VoiceSettings.autoDowngrade ? tracker.tier : 0
        // `defaults write com.nyaaorick.inputmethod.TypelessRev memoryTierOverride N` forces a tier for testing.
        if let forced = UserDefaults.standard.object(forKey: "memoryTierOverride") as? Int {
            target = max(0, min(MemoryTierTracker.maximum, forced))
        }
        let old = Self.tier
        guard target != old else { return }
        Self.tier = target
        var unloaded: [String] = []
        if target >= 1, old < 1 {
            Task { await WhisperEngine.shared.unload() }
            unloaded.append("whisper")
        }
        // At 2 the 9B gives way to the 4B; at 3 polish stops. Either way the loaded model goes, and
        // the engine loads whatever the tier allows at the next key press.
        if target >= 2, old < 2, PolishEngine.residency != .offloaded, PolishEngine.loadedModel != PolishEngine.effectiveModel {
            Task { await PolishEngine.shared.unload() }
            unloaded.append("polish")
        }
        if target == 3, PolishEngine.residency != .offloaded, !unloaded.contains("polish") {
            Task { await PolishEngine.shared.unload() }
            unloaded.append("polish")
        }
        Log.app.info(
            "memory: tier \(old) -> \(target) (\(self.tracker.pressure.rawValue, privacy: .public)), unloaded \(unloaded.isEmpty ? "nothing" : unloaded.joined(separator: ", "), privacy: .public)")
        NotificationCenter.default.post(name: .memoryTierChanged, object: nil)
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// The pressure right now, for the start: the source only reports changes.
    private static func currentPressure() -> MemoryPressure {
        switch sysctlInt("kern.memorystatus_vm_pressure_level") {
        case 4: .critical
        case 2: .warning
        default: .normal
        }
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

extension Notification.Name {
    static let memoryTierChanged = Notification.Name("TypelessRevMemoryTierChanged")
}
