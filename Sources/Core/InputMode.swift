import Foundation

/// The two states of the input method. English is the default and a true pass-through;
/// Chinese is pinyin through Rime.
enum InputMode: Equatable {
    case english
    case chinese

    mutating func toggle() {
        self = self == .english ? .chinese : .english
    }

    /// Shown briefly after the user switches. Never shown when a field gains focus.
    var announcement: String {
        switch self {
        case .english: return "Switch to English mode"
        case .chinese: return "Switch to Chinese mode"
        }
    }

    /// The Caps Lock key, which is the 中/英 key on a Mac sold in China: a tap switches the
    /// language, a long press toggles Caps Lock.
    static let switchKeyCode: UInt16 = 57
}

enum ModeKeyAction: Equatable {
    /// Released before the hold threshold: switch between English and Chinese.
    case tap
    /// Held past the threshold: toggle Caps Lock, and drop to English.
    case longPress
}

/// Tells a tap of the 中/英 key from a long press.
///
/// macOS reports the key going down as a Caps Lock `flagsChanged` event and offers no reliable
/// release event, so the controller polls the key's physical state and feeds the times in here.
/// `held` fires the long press as soon as the threshold passes, while the key is still down.
struct ModeKeyClassifier {
    static let holdThreshold: TimeInterval = 0.5

    private var pressedAt: TimeInterval?
    private var firedLongPress = false

    var isTracking: Bool { pressedAt != nil }

    mutating func press(at time: TimeInterval) {
        pressedAt = time
        firedLongPress = false
    }

    /// Call while the key is still down. Returns `.longPress` once, when the threshold passes.
    mutating func held(at time: TimeInterval) -> ModeKeyAction? {
        guard let pressedAt, !firedLongPress, time - pressedAt >= Self.holdThreshold else { return nil }
        firedLongPress = true
        return .longPress
    }

    /// Call when the key is up. Returns nil when the long press already fired, or nothing was tracked.
    mutating func release(at time: TimeInterval) -> ModeKeyAction? {
        defer { reset() }
        guard let pressedAt, !firedLongPress else { return nil }
        return time - pressedAt >= Self.holdThreshold ? .longPress : .tap
    }

    mutating func reset() {
        pressedAt = nil
        firedLongPress = false
    }
}
