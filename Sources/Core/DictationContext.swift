import Foundation

/// The field around the cursor when the push-to-talk key went down. The polish model reads it
/// to follow the topic and the sentence; it is never written back, and never logged.
struct DictationContext: Equatable, Sendable {
    /// Where `before` and `after` came from: this input method's own record of what it just
    /// wrote, the field itself, or nowhere (the app does not share its text).
    enum Source: String, Sendable {
        case ledger, field, none
    }

    static let beforeLimit = 200
    static let afterLimit = 20

    let style: AppStyle
    /// Up to `beforeLimit` characters before the cursor, or nil.
    let before: String?
    /// Up to `afterLimit` characters after the cursor (after the selection, which dictation replaces), or nil.
    let after: String?
    let source: Source

    init(style: AppStyle, before: String?, after: String?, source: Source) {
        self.style = style
        self.before = Self.clean(before.map { String($0.suffix(Self.beforeLimit)) })
        self.after = Self.clean(after.map { String($0.prefix(Self.afterLimit)) })
        self.source = source
    }

    /// A range cut through a surrogate pair decodes with U+FFFD at its edge; drop it. Empty is nil.
    private static func clean(_ text: String?) -> String? {
        guard var text else { return nil }
        while text.first == "\u{FFFD}" { text.removeFirst() }
        while text.last == "\u{FFFD}" { text.removeLast() }
        return text.isEmpty ? nil : text
    }
}
