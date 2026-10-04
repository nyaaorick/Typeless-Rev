import Carbon

enum KeyboardLayout {
    /// Rime wants raw US-layout keys, whatever layout the user last typed on.
    static let pinyinBase = "com.apple.keylayout.ABC"

    static let englishKey = "englishLayout"

    /// The layout English mode types with: the one picked in the menu while it is still enabled,
    /// otherwise ABC. It is a setting, not read from the system: asking macOS for the current
    /// ASCII-capable layout returned the input method's own last override, so one stray
    /// Spanish-ISO stuck for good and Shift+/ typed `_` (roadmap B6).
    static var english: String {
        if let chosen = UserDefaults.standard.string(forKey: englishKey), choices.contains(where: { $0.id == chosen }) {
            return chosen
        }
        return pinyinBase
    }

    static func setEnglish(_ id: String) {
        UserDefaults.standard.set(id, forKey: englishKey)
    }

    /// The keyboard layouts enabled in System Settings that can type English: (id, name).
    static var choices: [(id: String, name: String)] {
        let filter = [
            kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String,
            kTISPropertyInputSourceIsASCIICapable as String: true,
        ] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        return sources.compactMap { source in
            guard let id = string(source, kTISPropertyInputSourceID) else { return nil }
            return (id, string(source, kTISPropertyLocalizedName) ?? id)
        }
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}

/// macOS turns on secure event input while a password field has focus (and while an app such as
/// Terminal holds "Secure Keyboard Entry"). Nothing here may listen or compose then.
enum SecureInput {
    static var isActive: Bool { IsSecureEventInputEnabled() }
}
