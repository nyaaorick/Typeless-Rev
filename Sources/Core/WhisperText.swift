import Foundation

/// What goes into Whisper besides the audio, and what to keep of what comes out.
enum WhisperText {
    /// Whisper reads at most half its 448-token context as prompt; stay well inside it.
    static let maxPromptTokens = 200
    /// Shortest audio worth transcribing: below this a press is a tap, and Whisper tends to invent.
    static let minimumSeconds = 0.4

    /// The prompt: the text before the cursor (its tail, which is what the speech continues),
    /// then the hint terms. Whisper takes it as the text preceding the audio, so it biases spelling
    /// and vocabulary without being transcribed.
    static func prompt(before: String?, hints: [String]) -> String? {
        var parts: [String] = []
        if !hints.isEmpty { parts.append(hints.joined(separator: ", ") + ".") }
        if let before = before?.trimmingCharacters(in: .whitespacesAndNewlines), !before.isEmpty {
            parts.append(String(before.suffix(300)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Whisper's language code for the Speech Language setting: nil (detect) for auto.
    static func language(for setting: String, autoDetect: String = "auto") -> String? {
        guard setting != autoDetect else { return nil }
        let code = setting.split(separator: "-").first.map(String.init)?.lowercased()
        return code?.isEmpty == false ? code : nil
    }

    /// Lines Whisper is known to invent over silence or noise, learned from subtitled video.
    static let inventedLines: [String] = [
        "thank you for watching", "thanks for watching", "please subscribe", "subtitles by",
        "字幕由", "字幕提供", "请不吝点赞", "谢谢观看", "感谢观看", "明镜与点点栏目",
    ]

    /// Whole replies Whisper gives for a breath or a click: never trusted on their own.
    static let inventedWords: Set<String> = ["you", "thank you", "bye", "okay", "嗯", "啊"]

    /// The transcript with special tokens removed and whitespace tidied, ASCII punctuation next to
    /// Chinese made full-width, or nil when nothing is left or all of it is a line Whisper invents
    /// over silence.
    static func clean(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let bare = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        if bare.isEmpty || inventedWords.contains(bare)
            || inventedLines.contains(where: { bare.hasPrefix($0) && bare.count <= $0.count + 25 })
        {
            return nil
        }
        return fullWidthPunctuation(text)
    }

    /// Whisper writes "你好,世界." with ASCII marks; after a Han character they become "，" and "。".
    static func fullWidthPunctuation(_ text: String) -> String {
        let marks: [Character: Character] = [",": "，", ".": "。", "?": "？", "!": "！", ":": "：", ";": "；"]
        var result = ""
        var previous: Character?
        for character in text {
            if let previous, previous.unicodeScalars.first?.properties.isIdeographic == true,
                let wide = marks[character]
            {
                result.append(wide)
            } else {
                result.append(character)
            }
            previous = character
        }
        // A space Whisper left after a now full-width mark is not wanted in Chinese.
        return result.replacingOccurrences(of: "([，。？！：；]) ", with: "$1", options: .regularExpression)
    }

    /// True when the loudest stretch of `samples` (16 kHz) is too quiet to be speech: Whisper
    /// would only invent something.
    static func isSilent(_ samples: [Float], threshold: Float = 0.01) -> Bool {
        let window = 1_600  // 0.1 s
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + window)
            var sum: Float = 0
            for index in start..<end { sum += samples[index] * samples[index] }
            if (sum / Float(end - start)).squareRoot() >= threshold { return false }
            start = end
        }
        return true
    }
}
