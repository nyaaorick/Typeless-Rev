import XCTest

final class WhisperTextTests: XCTestCase {
    func testPromptPutsHintsBeforeTheFieldText() {
        XCTAssertEqual(
            WhisperText.prompt(before: "  check the pipeline ", hints: ["pipeline", "polish"]),
            "pipeline, polish. check the pipeline")
    }

    func testPromptKeepsTheTailOfALongField() {
        let before = String(repeating: "a", count: 500) + "END"
        let prompt = WhisperText.prompt(before: before, hints: [])
        XCTAssertEqual(prompt?.count, 300)
        XCTAssertTrue(prompt?.hasSuffix("END") ?? false)
    }

    func testNoPromptWithoutContext() {
        XCTAssertNil(WhisperText.prompt(before: nil, hints: []))
        XCTAssertNil(WhisperText.prompt(before: "   ", hints: []))
    }

    func testLanguageCodes() {
        XCTAssertNil(WhisperText.language(for: "auto"))
        XCTAssertEqual(WhisperText.language(for: "zh-CN"), "zh")
        XCTAssertEqual(WhisperText.language(for: "en-US"), "en")
        XCTAssertEqual(WhisperText.language(for: "ja-JP"), "ja")
    }

    func testCleanRemovesSpecialTokensAndSpaces() {
        XCTAssertEqual(WhisperText.clean("<|en|><|transcribe|>  Hello   world. <|endoftext|>"), "Hello world.")
    }

    func testCleanDropsEmptyAndInventedLines() {
        XCTAssertNil(WhisperText.clean("  <|endoftext|> "))
        XCTAssertNil(WhisperText.clean("..."))
        XCTAssertNil(WhisperText.clean("Thank you for watching!"))
        XCTAssertNil(WhisperText.clean("字幕由Amara.org社区提供"))
    }

    func testCleanKeepsRealSpeechThatMentionsAPhrase() {
        let text = "Thanks for watching the build, now let's check the current pipeline and fix the tests."
        XCTAssertEqual(WhisperText.clean(text), text)
    }

    func testCleanDropsALoneInventedWord() {
        XCTAssertNil(WhisperText.clean("you"))
        XCTAssertNil(WhisperText.clean(" You. "))
        XCTAssertEqual(WhisperText.clean("you can push now"), "you can push now")
    }

    func testChinesePunctuationBecomesFullWidth() {
        XCTAssertEqual(WhisperText.clean("你好,这是一个测试."), "你好，这是一个测试。")
        XCTAssertEqual(WhisperText.clean("我要去Costco买milk, 然后回家."), "我要去Costco买milk, 然后回家。")
        XCTAssertEqual(WhisperText.clean("Hello, world."), "Hello, world.")
    }

    func testSilenceDetection() {
        XCTAssertTrue(WhisperText.isSilent([Float](repeating: 0, count: 32_000)))
        XCTAssertTrue(WhisperText.isSilent([Float](repeating: 0.002, count: 32_000)))
        var speech = [Float](repeating: 0, count: 32_000)
        for index in 8_000..<9_600 { speech[index] = index % 2 == 0 ? 0.2 : -0.2 }
        XCTAssertFalse(WhisperText.isSilent(speech))
        XCTAssertTrue(WhisperText.isSilent([]))
    }
}
