import AppKit

/// Everything about the 中/英 key (Caps Lock), in one place.
///
/// The real lock is never written. Earlier versions turned it off again through IOHID after each
/// language switch, and that write does not always reach the window server: a later press then
/// changed nothing the window server could see, arrived as no event at all, and had to be pressed
/// twice (roadmap B5a). Now the real lock simply follows the key, so the keyboard light comes and
/// goes with each press and means nothing; every Caps Lock event is one press; and Caps Lock as
/// the user means it is this guard's own state, turned on and off with Shift + 中/英.
///
/// One instance is shared by every text field, like the real lock. Main thread only.
final class CapsLockGuard {
    enum Action: Equatable {
        case switchLanguage
        case capsLockOn
        case capsLockOff
    }

    static let shared = CapsLockGuard()

    /// Some apps deliver the same Caps Lock event twice, 5 to 40 ms apart.
    static let duplicateWindow: TimeInterval = 0.1

    /// Caps Lock as the user means it: letters in capitals, English only.
    private(set) var isOn = false
    private var lastPressAt: TimeInterval?

    /// The event IMK passes on for the key does not carry Shift, so the keyboard is asked too.
    static func shiftHeld(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.shift) || CGEventSource.flagsState(.combinedSessionState).contains(.maskShift)
    }

    /// One Caps Lock `flagsChanged` event. The lock state it carries is ignored: it only says
    /// where the real lock happens to be, and each event is one press of the key.
    func press(shift: Bool, at time: TimeInterval) -> Action? {
        if let lastPressAt, time - lastPressAt < Self.duplicateWindow { return nil }
        lastPressAt = time
        if shift {
            isOn.toggle()
            return isOn ? .capsLockOn : .capsLockOff
        }
        // With Caps Lock on, the key alone turns it off first; the language stays English.
        if isOn {
            isOn = false
            return .capsLockOff
        }
        return .switchLanguage
    }

    /// In English mode, the text a key should type, or nil to leave the key to the host app.
    ///
    /// The real lock is on after every other press, so letters cannot be left to the host app
    /// while it is on: the case comes from this guard instead, and Shift flips it, as on macOS.
    /// Anything but a plain letter (or a Command, Control or Option combination) goes through.
    func englishText(_ characters: String?, flags: NSEvent.ModifierFlags) -> String? {
        guard isOn || flags.contains(.capsLock),
            flags.isDisjoint(with: [.command, .control, .option]),
            let characters, characters.count == 1, characters.first?.isLetter == true
        else { return nil }
        return isOn != flags.contains(.shift) ? characters.uppercased() : characters.lowercased()
    }
}
