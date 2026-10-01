import Foundation

enum SpeechLanguage: Equatable {
    case english
    case chinese
}

/// What one recognizer has heard so far.
struct RecognitionTrack {
    private var transcript = TranscriptAccumulator()
    private var confidenceSum = 0.0
    private var confidenceWeight = 0

    var text: String { transcript.text }

    /// Mean confidence (0...1) over the finalized text, weighted by length. Volatile results
    /// carry no confidence, so this is nil until the first final result.
    var confidence: Double? {
        confidenceWeight > 0 ? confidenceSum / Double(confidenceWeight) : nil
    }

    /// `confidence` is the sum of confidence times characters over the result's runs, and the
    /// number of characters it covers.
    mutating func apply(_ text: String, isFinal: Bool, confidence: (sum: Double, weight: Int)? = nil) {
        transcript.apply(text, isFinal: isFinal)
        if isFinal, let confidence {
            confidenceSum += confidence.sum
            confidenceWeight += confidence.weight
        }
    }
}

/// Picks the language of an utterance from an English and a Mandarin recognizer that heard
/// the same audio.
///
/// Measured with synthesized speech (`--selftest-speech`): the Mandarin recognizer is not a
/// usable judge on its own, because it writes English speech down just as confidently as the
/// English one (0.87 against 0.81). What separates the languages is the script it produces
/// (Han characters only when Chinese was spoken) and how the English recognizer fares: it
/// scores 0.2 on Mandarin speech and 0.8 or more on English.
enum LanguagePicker {
    /// Below this the English recognizer is not really hearing English.
    static let englishConfidenceFloor = 0.6
    /// A Han share below this, with a confident English transcript, reads as English
    /// with a Chinese name or word in it.
    static let mostlyEnglishHanShare = 0.25

    /// Share of Han ideographs among the letters of `text`, 0 when there are none.
    static func hanShare(_ text: String) -> Double {
        var han = 0
        var letters = 0
        for scalar in text.unicodeScalars {
            if scalar.properties.isIdeographic {
                han += 1
                letters += 1
            } else if scalar.properties.isAlphabetic {
                letters += 1
            }
        }
        return letters == 0 ? 0 : Double(han) / Double(letters)
    }

    /// The transcript to preview while the user is still speaking. Volatile results have no
    /// confidence, so this goes by script alone.
    static func liveLeader(english: RecognitionTrack, chinese: RecognitionTrack) -> SpeechLanguage {
        if hanShare(chinese.text) > 0 { return .chinese }
        return english.text.isEmpty ? .chinese : .english
    }

    /// The transcript to commit. `hint` is the language of the input mode, used only when the
    /// two recognizers are equally sure of themselves.
    static func winner(
        english: RecognitionTrack, chinese: RecognitionTrack, hint: SpeechLanguage?
    ) -> SpeechLanguage {
        let han = hanShare(chinese.text)
        // The Mandarin recognizer wrote no Chinese: English speech, or nothing at all.
        if han == 0 { return english.text.isEmpty ? .chinese : .english }
        // It did, and the English recognizer is not convinced by what it heard.
        guard let confidence = english.confidence, confidence >= englishConfidenceFloor, !english.text.isEmpty
        else { return .chinese }
        // Both are convinced.
        if let hint { return hint }
        return han < mostlyEnglishHanShare ? .english : .chinese
    }
}
