import Foundation

/// Decides the mode a text field gets when it gains focus.
///
/// Every focus starts in English, except a bounce: system UI such as Control Center can take
/// input for a moment, so the field is deactivated and activated again. Resetting then silently
/// dropped Chinese, and the user's next 中/英 press only brought it back.
struct FocusBounce {
    /// Focus back within this long counts as a bounce, not a new visit.
    static let window: TimeInterval = 3

    private var lostAt: TimeInterval?

    mutating func deactivated(at time: TimeInterval) {
        lostAt = time
    }

    /// The mode to start in. `current` is what the field had when it lost focus.
    mutating func modeOnActivation(current: InputMode, at time: TimeInterval) -> InputMode {
        defer { lostAt = nil }
        guard let lostAt, time - lostAt < Self.window else { return .english }
        return current
    }
}
