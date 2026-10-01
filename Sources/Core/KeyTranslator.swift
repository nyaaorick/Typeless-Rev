import AppKit

/// Modifier bits as librime (X11 `XK_*` state) expects them.
enum RimeModifier {
    static let shift: Int32 = 1 << 0
    static let lock: Int32 = 1 << 1
    static let control: Int32 = 1 << 2
    static let alt: Int32 = 1 << 3
    static let `super`: Int32 = 1 << 26
}

struct RimeKeyEvent: Equatable {
    var keycode: Int32
    var mask: Int32
}

/// Translates AppKit key events into the keysym + modifier-mask pairs librime consumes.
enum KeyTranslator {
    static func modifierMask(_ flags: NSEvent.ModifierFlags) -> Int32 {
        var mask: Int32 = 0
        if flags.contains(.shift) { mask |= RimeModifier.shift }
        if flags.contains(.capsLock) { mask |= RimeModifier.lock }
        if flags.contains(.control) { mask |= RimeModifier.control }
        if flags.contains(.option) { mask |= RimeModifier.alt }
        if flags.contains(.command) { mask |= RimeModifier.super }
        return mask
    }

    /// Returns nil for keys librime has no use for, so the host app keeps them.
    static func keyDown(
        keyCode: UInt16,
        charactersIgnoringModifiers characters: String?,
        flags: NSEvent.ModifierFlags
    ) -> RimeKeyEvent? {
        let mask = modifierMask(flags)

        if let keysym = specialKeys[keyCode] {
            return RimeKeyEvent(keycode: keysym, mask: mask)
        }

        guard var value = characters?.unicodeScalars.first?.value else { return nil }
        // Below space, DEL, and the private-use block AppKit uses for function keys.
        guard value >= 0x20, value != 0x7f, !(0xF700...0xF8FF).contains(value) else { return nil }

        // charactersIgnoringModifiers already folds in Shift but not Caps Lock.
        if (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) {
            let upper = flags.contains(.shift) != flags.contains(.capsLock)
            value = (value | 0x20) - (upper ? 0x20 : 0)
        }

        // Latin-1 keysyms equal their code points; everything else is 0x01000000 + code point.
        let keysym = value < 0x100 ? value : 0x0100_0000 | value
        return RimeKeyEvent(keycode: Int32(bitPattern: keysym), mask: mask)
    }

    // MARK: - Tables

    /// macOS virtual key code -> X11 keysym.
    private static let specialKeys: [UInt16: Int32] = {
        var t: [UInt16: Int32] = [
            49: 0x0020,  // Space
            36: 0xff0d,  // Return
            76: 0xff8d,  // Keypad Enter
            51: 0xff08,  // Backspace
            117: 0xffff,  // Forward delete
            48: 0xff09,  // Tab
            53: 0xff1b,  // Escape
            123: 0xff51, 126: 0xff52, 124: 0xff53, 125: 0xff54,  // Left, Up, Right, Down
            115: 0xff50, 119: 0xff57,  // Home, End
            116: 0xff55, 121: 0xff56,  // Page Up, Page Down
            71: 0xff0b,  // Keypad Clear
            65: 0xffae, 67: 0xffaa, 69: 0xffab, 75: 0xffaf, 78: 0xffad, 81: 0xffbd,  // KP . * + / - =
        ]
        // F1...F12
        let fKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in fKeys.enumerated() { t[code] = Int32(0xffbe + i) }
        // Keypad 0...9
        let keypad: [UInt16] = [82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
        for (i, code) in keypad.enumerated() { t[code] = Int32(0xffb0 + i) }
        return t
    }()
}
