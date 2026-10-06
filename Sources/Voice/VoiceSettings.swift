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
    static let polishOffloadedKey = "polishOffloaded"
    static let speechEngineKey = "speechEngine"
    static let polishModelKey = "polishModel"
    static let autoDowngradeKey = "autoDowngrade"
    static let whisperOffloadedKey = "whisperOffloaded"

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

    /// True after the menu's Offload: the polish model stays on disk, out of memory, until Load.
    static var polishOffloaded: Bool {
        UserDefaults.standard.bool(forKey: polishOffloadedKey)
    }

    static func setPolishOffloaded(_ offloaded: Bool) {
        UserDefaults.standard.set(offloaded, forKey: polishOffloadedKey)
    }

    /// Which recognizer writes the final text. Apple's always runs too: it shows the live text and
    /// stands in whenever Whisper is not loaded or fails.
    enum SpeechEngine: String, CaseIterable {
        case apple, whisper

        var title: String {
            switch self {
            case .apple: "Apple Speech"
            case .whisper: "Whisper (large-v3-turbo)"
            }
        }
    }

    static var speechEngine: SpeechEngine {
        UserDefaults.standard.string(forKey: speechEngineKey).flatMap(SpeechEngine.init(rawValue:)) ?? .apple
    }

    static func setSpeechEngine(_ engine: SpeechEngine) {
        UserDefaults.standard.set(engine.rawValue, forKey: speechEngineKey)
    }

    /// True after the menu's Offload: the Whisper model stays on disk, out of memory, until Load.
    static var whisperOffloaded: Bool {
        UserDefaults.standard.bool(forKey: whisperOffloadedKey)
    }

    static func setWhisperOffloaded(_ offloaded: Bool) {
        UserDefaults.standard.set(offloaded, forKey: whisperOffloadedKey)
    }

    /// The polish model in use: only this one is installed into, loaded, and offloaded.
    static var polishModel: PolishModel {
        UserDefaults.standard.string(forKey: polishModelKey).flatMap(PolishModel.init(rawValue:)) ?? .qwen4b
    }

    static func setPolishModel(_ model: PolishModel) {
        UserDefaults.standard.set(model.rawValue, forKey: polishModelKey)
    }

    /// Whether models step down on their own under memory pressure (`MemoryGovernor`). On by default.
    static var autoDowngrade: Bool {
        UserDefaults.standard.object(forKey: autoDowngradeKey) as? Bool ?? true
    }

    static func setAutoDowngrade(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: autoDowngradeKey)
    }

    static var pushToTalkKey: PushToTalkKey {
        UserDefaults.standard.string(forKey: pushToTalkKeyKey).flatMap(PushToTalkKey.init(rawValue:))
            ?? .rightOption
    }
}
