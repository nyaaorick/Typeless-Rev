import XCTest

final class SpeechLanguageTests: XCTestCase {
    private func track(_ text: String, confidence: Double? = nil) -> RecognitionTrack {
        var track = RecognitionTrack()
        if let confidence {
            track.apply(text, isFinal: true, confidence: (sum: confidence * Double(text.count), weight: text.count))
        } else {
            track.apply(text, isFinal: false)
        }
        return track
    }

    // MARK: - Track

    func testConfidenceIsLengthWeightedAndOnlyFromFinals() {
        var t = RecognitionTrack()
        XCTAssertNil(t.confidence)
        t.apply("guess", isFinal: false, confidence: (sum: 5, weight: 5))
        XCTAssertNil(t.confidence)
        t.apply("ab", isFinal: true, confidence: (sum: 2 * 1.0, weight: 2))
        t.apply("cdef", isFinal: true, confidence: (sum: 4 * 0.5, weight: 4))
        XCTAssertEqual(t.confidence!, (2.0 + 2.0) / 6.0, accuracy: 1e-9)
        XCTAssertEqual(t.text, "abcdef")
    }

    func testFinalWithoutConfidenceLeavesItUnknown() {
        var t = RecognitionTrack()
        t.apply("hello", isFinal: true)
        XCTAssertNil(t.confidence)
    }

    // MARK: - Script

    func testHanShare() {
        XCTAssertEqual(LanguagePicker.hanShare("hello world"), 0)
        XCTAssertEqual(LanguagePicker.hanShare("你好"), 1)
        XCTAssertEqual(LanguagePicker.hanShare("你好 ab"), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LanguagePicker.hanShare("，。 123"), 0)
        XCTAssertEqual(LanguagePicker.hanShare(""), 0)
    }

    // MARK: - Live preview

    func testLiveLeaderFollowsTheScript() {
        XCTAssertEqual(LanguagePicker.liveLeader(english: track("Ni hao"), chinese: track("你好")), .chinese)
        XCTAssertEqual(LanguagePicker.liveLeader(english: track("Hello"), chinese: track("Hellowo")), .english)
        XCTAssertEqual(LanguagePicker.liveLeader(english: track(""), chinese: track("")), .chinese)
        XCTAssertEqual(LanguagePicker.liveLeader(english: track("Hello"), chinese: track("")), .english)
    }

    // MARK: - Final decision, with the numbers measured on synthesized speech

    func testEnglishSpeechIsEnglishDespiteTheMandarinModelBeingMoreConfident() {
        let english = track("Hello, world. This is a speech test.", confidence: 0.81)
        let chinese = track("Helloworld this is a speach test.", confidence: 0.87)
        XCTAssertEqual(LanguagePicker.winner(english: english, chinese: chinese, hint: nil), .english)
        XCTAssertEqual(LanguagePicker.winner(english: english, chinese: chinese, hint: .chinese), .english)
    }

    func testMandarinSpeechIsChineseWhateverTheHint() {
        let english = track("Ni hao, shi ji, shi, yi, yi.", confidence: 0.18)
        let chinese = track("你好，世界。这是一个语音测试。", confidence: 0.91)
        XCTAssertEqual(LanguagePicker.winner(english: english, chinese: chinese, hint: nil), .chinese)
        XCTAssertEqual(LanguagePicker.winner(english: english, chinese: chinese, hint: .english), .chinese)
    }

    func testChineseWithEnglishWordsIsChinese() {
        // The English recognizer heard nothing it could use.
        let chinese = track("我今天要去 Costco 买一些 milk，然后回家写 swift 代码。", confidence: 0.92)
        XCTAssertEqual(LanguagePicker.winner(english: track(""), chinese: chinese, hint: .english), .chinese)
    }

    func testNothingHeardIsEmptyChinese() {
        XCTAssertEqual(LanguagePicker.winner(english: track(""), chinese: track(""), hint: .english), .chinese)
    }

    func testBothConvincedFallsBackToTheHintThenToTheHanShare() {
        let english = track("Please send it to Wang Wei tomorrow", confidence: 0.9)
        let mostlyEnglish = track("Please send it to 王伟 tomorrow", confidence: 0.9)
        XCTAssertEqual(LanguagePicker.winner(english: english, chinese: mostlyEnglish, hint: .chinese), .chinese)
        XCTAssertEqual(LanguagePicker.winner(english: english, chinese: mostlyEnglish, hint: .english), .english)
        XCTAssertEqual(LanguagePicker.winner(english: english, chinese: mostlyEnglish, hint: nil), .english)
        let mostlyChinese = track("我明天会发给 Wang 你", confidence: 0.9)
        XCTAssertEqual(LanguagePicker.winner(english: english, chinese: mostlyChinese, hint: nil), .chinese)
    }

    func testAnEnglishTranscriptWithoutConfidenceDoesNotOutvoteHan() {
        let english = track("Ni hao")  // volatile only
        let chinese = track("你好", confidence: 0.9)
        XCTAssertEqual(LanguagePicker.winner(english: english, chinese: chinese, hint: .english), .chinese)
    }
}
