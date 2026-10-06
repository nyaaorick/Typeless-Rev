import Foundation

/// macOS's system-wide memory pressure: the green, yellow and red of Activity Monitor's graph.
enum MemoryPressure: String, Equatable, Sendable {
    case normal, warning, critical
}

/// How far the voice models step down under memory pressure, from the pressure and how long it
/// has lasted:
///
/// - 0: as the user chose.
/// - 1: Whisper unloaded (Apple's recognizer writes the text).
/// - 2: also the 9B polish model swapped for the 4B.
/// - 3: Whisper and polish unloaded (the raw transcript is inserted).
///
/// It climbs at once and comes down slowly: only after `recoverAfter` of normal pressure, so a
/// brief dip does not reload gigabytes only to unload them again.
struct MemoryTierTracker: Equatable {
    /// A warning that lasts this long steps up from 1 to 2.
    static let escalateAfter: TimeInterval = 30
    /// Normal pressure for this long brings the tier back to 0.
    static let recoverAfter: TimeInterval = 90
    static let maximum = 3

    private(set) var tier = 0
    private(set) var pressure = MemoryPressure.normal
    /// When `pressure` took its current value.
    private var since: TimeInterval = 0

    /// Records a pressure reading taken at `now` (seconds on any monotonic clock).
    mutating func update(_ pressure: MemoryPressure, at now: TimeInterval) {
        if pressure != self.pressure {
            self.pressure = pressure
            since = now
        }
        tick(at: now)
    }

    /// Re-evaluates the time-based steps; call it every few seconds.
    mutating func tick(at now: TimeInterval) {
        let lasted = now - since
        switch pressure {
        case .critical:
            tier = 3
        case .warning:
            tier = max(tier, lasted >= Self.escalateAfter ? 2 : 1)
        case .normal:
            if lasted >= Self.recoverAfter { tier = 0 }
        }
    }
}

enum MemoryBudget {
    /// The percentage of RAM that must still be free after a model loads. Small on purpose: the
    /// free percentage leaves out memory macOS can reclaim cheaply (44% "free" on a 16 GB Mac under
    /// no pressure at all), so a larger reserve would refuse loads that are fine. The pressure
    /// signal covers the rest.
    static let reservePercent: Int64 = 5

    /// True when loading `bytes` leaves at least `reservePercent` of `totalBytes` free, given the
    /// system's free-memory percentage (`kern.memorystatus_level`).
    static func canLoad(bytes: Int64, freePercent: Int, totalBytes: Int64) -> Bool {
        let free = totalBytes / 100 * Int64(max(0, min(100, freePercent)))
        return free - bytes >= totalBytes / 100 * reservePercent
    }
}
