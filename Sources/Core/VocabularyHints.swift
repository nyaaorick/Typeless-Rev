import Foundation

/// Words the speech recognizer should expect, handed to it as contextual strings so that it picks
/// "current pipeline" over a sound-alike such as "popcorn pipeline".
///
/// Two sources: distinctive words already in the field before the cursor (most recent first), and a
/// fixed vocabulary of terms a general speech model tends to mishear. Chinese text in the field is
/// skipped: picking keywords out of it would need a word segmenter.
enum VocabularyHints {
    /// The most terms handed to the recognizer, and the most of those taken from the field.
    static let limit = 100
    static let fieldLimit = 40

    /// Terms for any app.
    static let general: [String] = [
        "Typeless", "Rime", "pinyin", "dictation", "transcript", "polish", "prompt", "model", "pipeline",
        "workflow", "context", "cursor", "input method", "push-to-talk", "Caps Lock", "macOS", "iPhone",
        "AI", "LLM", "Claude", "ChatGPT", "Qwen", "MLX", "token", "API", "app", "bug", "feature", "update",
    ]

    /// Terms added in code editors and terminals.
    static let code: [String] = [
        "commit", "push", "pull request", "PR", "merge", "rebase", "branch", "repo", "GitHub", "diff",
        "build", "deploy", "refactor", "debug", "test", "unit test", "lint", "compile", "runtime",
        "async", "await", "callback", "closure", "struct", "enum", "protocol", "class", "function",
        "variable", "parameter", "argument", "return", "import", "module", "package", "dependency",
        "Swift", "SwiftUI", "Xcode", "Python", "TypeScript", "JavaScript", "Rust", "Go", "JSON", "YAML",
        "regex", "CLI", "SDK", "endpoint", "schema", "database", "SQL", "cache", "config", "env",
        "localhost", "npm", "pip", "Homebrew", "Docker", "VS Code", "terminal", "shell", "bash", "zsh",
    ]

    /// Common English words that say nothing about the topic.
    static let stopwords: Set<String> = [
        "about", "above", "after", "again", "against", "also", "because", "been", "before", "being",
        "below", "between", "both", "but", "came", "could", "does", "doing", "done", "down", "during",
        "each", "even", "every", "from", "further", "gets", "going", "gonna", "good", "have", "having",
        "here", "into", "just", "know", "like", "look", "made", "make", "many", "maybe", "mean", "more",
        "most", "much", "must", "need", "never", "next", "only", "other", "ours", "over", "really",
        "right", "said", "same", "seem", "seems", "should", "some", "something", "still", "such", "sure",
        "take", "than", "thank", "thanks", "that", "their", "theirs", "them", "then", "there", "these",
        "they", "thing", "things", "think", "this", "those", "through", "under", "until", "very", "want",
        "wanna", "well", "were", "what", "when", "where", "which", "while", "will", "with", "would",
        "yeah", "your", "yours",
        "all", "and", "any", "are", "can", "did", "for", "get", "got", "had", "has", "how", "its", "let",
        "may", "new", "not", "now", "one", "our", "say", "see", "the", "too", "two", "use", "was", "way",
        "who", "why", "yes", "you",
    ]

    /// The terms for one utterance: words from `before` first, then the fixed vocabulary for `style`,
    /// without case-insensitive duplicates and at most `limit` long.
    static func terms(before: String?, style: AppStyle) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        func add(_ term: String) {
            guard result.count < limit, seen.insert(term.lowercased()).inserted else { return }
            result.append(term)
        }
        keywords(in: before ?? "").forEach(add)
        general.forEach(add)
        if style == .code { code.forEach(add) }
        return result
    }

    /// Distinctive words of `text`, most recent first, at most `fieldLimit`: identifiers
    /// (camelCase, snake_case, kebab-case, with digits), capitalized words, and other words of
    /// four letters or more that are not stopwords. Acronyms count from two letters, capitalized words from three.
    static func keywords(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for token in tokens(in: text).reversed() {
            guard result.count < fieldLimit, isDistinctive(token), seen.insert(token.lowercased()).inserted
            else { continue }
            result.append(token)
        }
        return result
    }

    /// Runs of ASCII letters and digits, joined by `_`, `-` or `.` inside a run ("file_name.swift").
    private static func tokens(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            while let last = current.last, "_-.".contains(last) { current.removeLast() }
            if !current.isEmpty { tokens.append(current) }
            current = ""
        }
        for character in text {
            if character.isASCII, character.isLetter || character.isNumber {
                current.append(character)
            } else if "_-.".contains(character), !current.isEmpty {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    private static func isDistinctive(_ token: String) -> Bool {
        guard token.contains(where: \.isLetter) else { return false }
        let isIdentifier =
            token.contains(where: { "_-.".contains($0) }) || token.contains(where: \.isNumber)
            || token.dropFirst().contains(where: \.isUppercase)
        if isIdentifier { return token.count >= 2 }
        if stopwords.contains(token.lowercased()) { return false }
        if token.count >= 2, token.allSatisfy(\.isUppercase) { return true }
        if token.first?.isUppercase == true { return token.count >= 3 }
        return token.count >= 4
    }
}
