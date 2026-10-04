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

    func testTimeoutGrowsWithLengthUpToTenSeconds() {
        XCTAssertEqual(PolishPrompt.timeout(for: ""), .seconds(3))
        XCTAssertEqual(PolishPrompt.timeout(for: String(repeating: "a", count: 100)), .milliseconds(5_500))
        XCTAssertEqual(PolishPrompt.timeout(for: String(repeating: "字", count: 1_000)), .seconds(10))
    }

    func testContextGoesIntoTheInstructionsNotTheMessage() {
        let context = DictationContext(style: .plain, before: "We met Alice.", after: "Thanks", source: .field)
        let instructions = PolishPrompt.instructions(style: .plain, context: context)
        XCTAssertTrue(instructions.hasPrefix(PolishPrompt.system))
        XCTAssertTrue(instructions.contains("«We met Alice.»"))
        XCTAssertTrue(instructions.contains("«Thanks»"))
    }

    func testWithoutContextTheInstructionsAreThePlainPrompt() {
        let empty = DictationContext(style: .plain, before: nil, after: nil, source: .none)
        XCTAssertEqual(PolishPrompt.instructions(style: .plain, context: empty), PolishPrompt.system)
        XCTAssertEqual(PolishPrompt.instructions(style: .plain), PolishPrompt.system)
    }

    func testInstructionsAddTheAppStyle() {
        XCTAssertTrue(PolishPrompt.instructions(style: .code).hasSuffix(AppStyle.code.hint!))
    }

    func testRejectsAReplyThatRepeatsTheContext() {
        let context = DictationContext(
            style: .plain, before: "The quarterly report is due on Friday.", after: nil, source: .field)
        XCTAssertNil(
            PolishPrompt.accept("Report is due on Friday. Let's meet at three.", for: "lets meet at three", context: context))
        XCTAssertEqual(
            PolishPrompt.accept("Let's meet at three.", for: "lets meet at three", context: context), "Let's meet at three.")
    }

    func testRepeatingWhatTheSpeakerSaidIsNotAnEcho() {
        let context = DictationContext(style: .plain, before: "see you on Friday", after: nil, source: .field)
        XCTAssertEqual(
            PolishPrompt.accept("Yes, see you on Friday.", for: "yes see you on Friday", context: context),
            "Yes, see you on Friday.")
    }
}
