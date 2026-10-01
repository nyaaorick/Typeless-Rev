/// Assembles the running transcript from SpeechTranscriber results.
///
/// Final results are permanent and arrive in order. A volatile result is the
/// recognizer's current guess for the audio after the last final one, so each
/// new volatile result replaces the previous one.
struct TranscriptAccumulator {
    private(set) var finalized = ""
    private(set) var volatile = ""

    var text: String { finalized + volatile }

    mutating func apply(_ text: String, isFinal: Bool) {
        if isFinal {
            finalized += text
            volatile = ""
        } else {
            volatile = text
        }
    }
}
