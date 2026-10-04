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

    /// The Caps Lock key, which is the 中/英 key on a Mac sold in China: a press switches the
    /// language. Shift with it is the real Caps Lock.
    static let switchKeyCode: UInt16 = 57
}
