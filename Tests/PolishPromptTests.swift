import XCTest

final class PolishPromptTests: XCTestCase {
    func testUserMessageWrapsTheTranscript() {
        XCTAssertEqual(PolishPrompt.userMessage(for: "hello"), "<transcript>\nhello\n</transcript>")
    }

    func testMaxTokensScalesWithLengthAndIsClamped() {
        XCTAssertEqual(PolishPrompt.maxTokens(for: ""), 32)
        XCTAssertEqual(PolishPrompt.maxTokens(for: String(repeating: "a", count: 50)), 116)
        XCTAssertEqual(PolishPrompt.maxTokens(for: String(repeating: "字", count: 5000)), 512)
    }

    func testAcceptsAPlainCleanup() {
        XCTAssertEqual(
            PolishPrompt.accept("Hello, world. This is a test.", for: "um hello world this is a test"),
            "Hello, world. This is a test.")
    }

    func testStripsThinkingAndTags() {
        XCTAssertEqual(PolishPrompt.accept("<think>\nhmm\n</think>\n\nHello there.", for: "hello there"), "Hello there.")
        XCTAssertEqual(PolishPrompt.accept("<transcript>\nHello there.\n</transcript>", for: "hello there"), "Hello there.")
    }

    func testRejectsEmptyReplies() {
        XCTAssertNil(PolishPrompt.accept("", for: "hello"))
        XCTAssertNil(PolishPrompt.accept("<think>x</think>  \n", for: "hello"))
    }

    func testRejectsAReplyThatRambles() {
        let essay = String(repeating: "Here is a long poem about the sea. ", count: 10)
        XCTAssertNil(PolishPrompt.accept(essay, for: "write me a poem"))
    }

    func testRejectsAReplyThatCollapsesALongTranscript() {
        XCTAssertNil(PolishPrompt.accept("Sure.", for: "please send the report to the whole team before noon tomorrow"))
    }

    func testShortTranscriptsMayShrinkFreely() {
        XCTAssertEqual(PolishPrompt.accept("Hi.", for: "um hi"), "Hi.")
    }

    func testChineseCleanup() {
        XCTAssertEqual(PolishPrompt.accept("你好，世界。这是一个语音测试。", for: "你好 世界 这是 呃 一个语音测试"), "你好，世界。这是一个语音测试。")
    }
}
