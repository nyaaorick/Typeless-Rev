import AppKit

/// Modifier keys that can act as the push-to-talk key. Right-hand keys only: the
/// left ones are part of too many shortcuts.
enum PushToTalkKey: String, CaseIterable {
    case rightOption
    case rightControl
    case rightCommand

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightControl: return 62
        case .rightCommand: return 54
        }
    }

    var title: String {
        switch self {
        case .rightOption: return "Right Option"
        case .rightControl: return "Right Control"
        case .rightCommand: return "Right Command"
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: return .option
        case .rightControl: return .control
        case .rightCommand: return .command
        }
    }
}

enum PushToTalkEvent: Equatable {
    case press
    case release
}

/// Turns `flagsChanged` events into press/release of the push-to-talk key.
///
/// `flags` only say whether *some* key of that modifier family is down, so the
/// detector tracks its own state: a second event for the same key while it is
/// down is always a release, even if the left-hand twin keeps the flag set.
struct PushToTalkDetector {
    var key: PushToTalkKey
    private(set) var isDown = false

    init(key: PushToTalkKey) {
        self.key = key
    }

    mutating func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> PushToTalkEvent? {
        guard keyCode == key.keyCode else { return nil }
        if isDown {
            isDown = false
            return .release
        }
        guard flags.contains(key.flag) else { return nil }
        isDown = true
        return .press
    }

    /// Forgets a held key, for example when focus moves away before the release arrives.
    mutating func reset() {
        isDown = false
    }
}
