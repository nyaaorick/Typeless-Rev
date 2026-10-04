import Foundation

/// The text before the cursor as of the last voice write, kept while nothing else touched the field.
///
/// Consecutive dictation is the common case, and then the text before the cursor is just what
/// was dictated a moment ago: this record answers for it without asking the app, which also
/// works in apps that do not share their text. Any key or loss of focus clears it, and so does
/// a cursor that moved (a click), when the app reports where the cursor is.
struct RecentCommit {
    /// The text before the cursor, at most `DictationContext.beforeLimit` characters.
    private(set) var tail = ""
    /// What followed the cursor when the run began; writing at the cursor leaves it in place.
    private(set) var following: String?
    /// The cursor just after the last write, in UTF-16 units, or nil when the app does not say.
    private(set) var caretAfter: Int?

    /// Voice wrote `inserted` at the cursor described by `context`: the run is now what preceded
    /// the cursor (from the field or from this record) followed by the new text.
    mutating func record(_ inserted: String, context: DictationContext?, caretAfter: Int?) {
        tail = String(((context?.before ?? "") + inserted).suffix(DictationContext.beforeLimit))
        following = context?.after
        self.caretAfter = caretAfter
    }

    mutating func invalidate() {
        self = RecentCommit()
    }

    /// The context for the next utterance, or nil when there is no run or the cursor has moved.
    /// A cursor the app does not report is taken as unmoved: at worst one space is misplaced.
    func context(style: AppStyle, currentCaret: Int?) -> DictationContext? {
        guard !tail.isEmpty else { return nil }
        if let caretAfter, let currentCaret, caretAfter != currentCaret { return nil }
        return DictationContext(style: style, before: tail, after: following, source: .ledger)
    }
}
