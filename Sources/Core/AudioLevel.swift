import Foundation

/// Turns microphone samples into a 0...1 position on a level meter.
enum AudioLevel {
    /// Quieter than this reads as empty, louder than the ceiling as full. Speech at a
    /// normal distance sits around -30 to -20 dBFS.
    private static let floorDB: Float = -55
    private static let ceilingDB: Float = -10

    static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// `rms` is full-scale amplitude, 0...1.
    static func meter(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db - floorDB) / (ceilingDB - floorDB)))
    }
}
