import XCTest

final class VoiceSpacingTests: XCTestCase {
    func testEnglishAfterASentenceGetsASpace() {
        XCTAssertEqual(VoiceSpacing.padded("It works.", before: ".", after: nil), " It works.")
        XCTAssertEqual(VoiceSpacing.padded("pm", before: "3", after: nil), " pm")
    }

    func testNoSpaceAfterWhitespaceOrAtTheStart() {
        XCTAssertEqual(VoiceSpacing.padded("It", before: " ", after: nil), "It")
        XCTAssertEqual(VoiceSpacing.padded("It", before: "\n", after: nil), "It")
        XCTAssertEqual(VoiceSpacing.padded("It", before: nil, after: nil), "It")
    }

    func testChineseTextNeverGetsALeadingSpace() {
        XCTAssertEqual(VoiceSpacing.padded("你好", before: "a", after: nil), "你好")
        XCTAssertEqual(VoiceSpacing.padded("你好", before: "中", after: nil), "你好")
    }

    func testEnglishAfterChineseGetsASpace() {
        XCTAssertEqual(VoiceSpacing.padded("OK", before: "得", after: nil), " OK")
    }

    func testNoSpaceAfterOpenersJoinersOrFullWidthPunctuation() {
        for opener: Character in ["(", "“", "\"", "/", "@", "#", "-", "（", "「"] {
            XCTAssertEqual(VoiceSpacing.padded("word", before: opener, after: nil), "word", "after \(opener)")
        }
        XCTAssertEqual(VoiceSpacing.padded("OK", before: "。", after: nil), "OK")
        XCTAssertEqual(VoiceSpacing.padded("OK", before: "，", after: nil), "OK")
    }

    func testSpaceBeforeAnEnglishWordThatFollows() {
        XCTAssertEqual(VoiceSpacing.padded("quick", before: " ", after: "f"), "quick ")
        XCTAssertEqual(VoiceSpacing.padded("Done.", before: nil, after: "N"), "Done. ")
        XCTAssertEqual(VoiceSpacing.padded("quick", before: " ", after: " "), "quick")
        XCTAssertEqual(VoiceSpacing.padded("quick", before: " ", after: "."), "quick")
        XCTAssertEqual(VoiceSpacing.padded("你好", before: nil, after: "a"), "你好")
    }

    func testBothEnds() {
        XCTAssertEqual(VoiceSpacing.padded("brown", before: "k", after: "f"), " brown ")
    }

    func testEmptyTextStaysEmpty() {
        XCTAssertEqual(VoiceSpacing.padded("", before: "a", after: "b"), "")
    }
}
