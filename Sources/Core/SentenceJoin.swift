import Foundation

/// Fits dictated English into a sentence already under way. Both the recognizer and the polish
/// model treat each utterance as a sentence of its own: a capital first word and a closing
/// period, even when the cursor sits mid-sentence (the model is told otherwise and still does it).
///
/// Only common function words are lowercased: a capital name such as "Joanna" is left alone.
enum SentenceJoin {
    static func fitted(_ text: String, before: String?, after: String?) -> String {
        var result = text
        if continuesSentence(before) { result = lowercasingFirstWord(result) }
        if let next = after?.first, next.isASCII, next.isLowercase,
            result.hasSuffix("."), !result.hasSuffix("..")
        {
            result.removeLast()
        }
        return result
    }

    /// True when the text before ends mid-sentence: in a word, a digit, or a comma-like mark.
    private static func continuesSentence(_ before: String?) -> Bool {
        guard let last = before?.last(where: { !$0.isWhitespace }) else { return false }
        return (last.isASCII && (last.isLetter || last.isNumber)) || [",", ";", ":"].contains(last)
    }

    private static func lowercasingFirstWord(_ text: String) -> String {
        let word = text.prefix { $0.isLetter }
        guard functionWords.contains(word.lowercased()), word.first?.isUppercase == true,
            word.dropFirst().allSatisfy({ $0.isLowercase })
        else { return text }
        return word.lowercased() + text.dropFirst(word.count)
    }

    private static let functionWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "nor", "so", "yet", "then", "because", "since", "although",
        "though", "if", "when", "while", "where", "which", "who", "that", "this", "these", "those", "as",
        "also", "not", "to", "of", "in", "on", "at", "for", "with", "by", "from", "about", "after", "before",
        "it", "its", "we", "they", "he", "she", "you", "my", "our", "your", "their", "his", "her", "there",
        "is", "are", "was", "were", "be", "will", "would", "can", "could", "should", "maybe", "just", "even",
    ]
}
