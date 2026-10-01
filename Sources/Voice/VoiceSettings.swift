import Foundation

/// Voice preferences, stored in `UserDefaults` and edited from the menu bar. (They can also be
/// set with `defaults write com.nyaaorick.inputmethod.TypelessRev <key> <value>`.)
enum VoiceSettings {
    /// Languages offered in the menu: (identifier, name). Each needs Apple's on-device model,
    /// which downloads the first time the language is used.
    static let localeChoices: [(id: String, name: String)] = [
        ("zh-CN", "Chinese (Mainland)"), ("zh-TW", "Chinese (Taiwan)"), ("zh-HK", "Chinese (Hong Kong)"),
        ("en-US", "English (US)"), ("en-GB", "English (UK)"),
        ("ja-JP", "Japanese"), ("ko-KR", "Korean"),
        ("fr-FR", "French"), ("de-DE", "German"), ("es-ES", "Spanish"),
    ]

    /// The `speechLocale` value that turns language detection on.
    static let autoDetect = "auto"

    static let localeKey = "speechLocale"
    static let pushToTalkKeyKey = "pushToTalkKey"
    static let polishEnabledKey = "polishEnabled"
    static let polishCrashesKey = "polishCrashes"
    static let polishDisabledByCrashKey = "polishDisabledByCrash"

    /// How long to wait for the polish step, loading included, before committing the raw text.
    static let polishTimeout: Duration = .seconds(3)

    /// Whether the transcript is polished by the local LLM. Defaults to on.
    static var polishEnabled: Bool {
        UserDefaults.standard.object(forKey: polishEnabledKey) as? Bool ?? true
    }

    /// What to listen for: both English and Mandarin by default (the language is detected from the
    /// speech), or the one language picked in the menu. `hint` is the language of the input mode.
    static func recognition(hint: SpeechLanguage?) -> Recognition {
        localeIdentifier == autoDetect ? .auto(hint: hint) : .fixed(Locale(identifier: localeIdentifier))
    }

    static var localeIdentifier: String {
        UserDefaults.standard.string(forKey: localeKey) ?? autoDetect
    }

    static func setLocale(_ identifier: String) {
        UserDefaults.standard.set(identifier, forKey: localeKey)
    }

    static func setPushToTalkKey(_ key: PushToTalkKey) {
        UserDefaults.standard.set(key.rawValue, forKey: pushToTalkKeyKey)
    }

    static func setPolishEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: polishEnabledKey)
        // The user's own choice replaces the automatic one.
        if enabled { setPolishDisabledByCrash(false) }
    }

    /// Runs in a row that died while the polish model was in use.
    static var polishCrashes: Int {
        UserDefaults.standard.integer(forKey: polishCrashesKey)
    }

    static func setPolishCrashes(_ count: Int) {
        UserDefaults.standard.set(count, forKey: polishCrashesKey)
    }

    /// True when polishing was switched off automatically after repeated crashes.
    static var polishDisabledByCrash: Bool {
        UserDefaults.standard.bool(forKey: polishDisabledByCrashKey)
    }

    static func setPolishDisabledByCrash(_ disabled: Bool) {
        UserDefaults.standard.set(disabled, forKey: polishDisabledByCrashKey)
    }

    static var pushToTalkKey: PushToTalkKey {
        UserDefaults.standard.string(forKey: pushToTalkKeyKey).flatMap(PushToTalkKey.init(rawValue:))
            ?? .rightOption
    }
}
