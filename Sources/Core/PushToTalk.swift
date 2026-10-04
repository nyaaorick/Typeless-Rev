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

    /// The device-dependent bit (`NX_DEVICER*KEYMASK`) for this key alone, which tells it apart
    /// from its left-hand twin.
    var deviceBit: UInt {
        switch self {
        case .rightOption: return 0x40
        case .rightControl: return 0x2000
        case .rightCommand: return 0x10
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
/// The key's own device bit says whether it is down. Each event is read as a state, never as a
/// toggle: some apps (SunBrowser, a Chromium browser) deliver the press twice, and a toggle read
/// the second copy as a release, ending dictation a few milliseconds after it started. Events
/// without device bits fall back to the modifier flag, which the left-hand twin can also set.
struct PushToTalkDetector {
    /// Every `NX_DEVICE*KEYMASK` bit: left and right Control, Shift, Command and Option.
    private static let deviceBits: UInt = 0x20FF

    var key: PushToTalkKey
    private(set) var isDown = false

    init(key: PushToTalkKey) {
        self.key = key
    }

    mutating func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> PushToTalkEvent? {
        guard keyCode == key.keyCode else { return nil }
        let down =
            flags.rawValue & Self.deviceBits != 0
            ? flags.rawValue & key.deviceBit != 0
            : flags.contains(key.flag)
        guard down != isDown else { return nil }
        isDown = down
        return down ? .press : .release
    }

    /// Forgets a held key, for example when focus moves away before the release arrives.
    mutating func reset() {
        isDown = false
    }
}
