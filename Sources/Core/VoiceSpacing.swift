import Foundation

/// Spaces around dictated text, so it does not run into its neighbours (`normally.It`).
///
/// Text that starts with a Latin letter or digit gets a space before it, unless it follows
/// whitespace, an opening bracket or quote, a joiner such as `/` or `@`, or full-width
/// punctuation (which carries its own space). Text that starts in Chinese never does. Text that
/// ends in a Latin letter, digit, or closing punctuation gets a space after it when an English
/// word follows straight on.
enum VoiceSpacing {
    static func padded(_ text: String, before previous: Character?, after next: Character?) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        if needsLeadingSpace(after: previous, inserting: text) { result = " " + result }
        if needsTrailingSpace(inserting: text, before: next) { result += " " }
        return result
    }

    static func needsLeadingSpace(after previous: Character?, inserting text: String) -> Bool {
        guard let first = text.first, isLatin(first), let previous else { return false }
        if previous.isWhitespace || noSpaceAfter.contains(previous) { return false }
        if previous.unicodeScalars.contains(where: isFullWidthPunctuation) { return false }
        return true
    }

    static func needsTrailingSpace(inserting text: String, before next: Character?) -> Bool {
        guard let last = text.last, let next, isLatin(next) else { return false }
        return isLatin(last) || closingPunctuation.contains(last)
    }

    private static func isLatin(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber)
    }

    /// Opening brackets and quotes, straight quotes (open or closed, there is no telling), and
    /// characters that join words: none of them wants a space after it.
    private static let noSpaceAfter: Set<Character> = [
        "(", "[", "{", "<", "“", "‘", "\"", "'", "/", "\\", "-", "_", "@", "#", "$", "~",
        "（", "【", "「", "『", "《", "〈",
    ]

    private static let closingPunctuation: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "]", "}"]

    /// CJK punctuation (U+3000 block) and full-width forms such as `，` and `！`.
    private static func isFullWidthPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        (0x3000...0x303F).contains(scalar.value)
            || ((0xFF00...0xFFEF).contains(scalar.value) && !scalar.properties.isAlphabetic
                && scalar.properties.numericType == nil)
    }
}
