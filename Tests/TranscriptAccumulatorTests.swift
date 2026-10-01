import XCTest

final class TranscriptAccumulatorTests: XCTestCase {
    func testVolatileResultsReplaceEachOther() {
        var transcript = TranscriptAccumulator()
        transcript.apply("hel", isFinal: false)
        transcript.apply("hello wor", isFinal: false)
        XCTAssertEqual(transcript.text, "hello wor")
    }

    func testFinalResultIsKeptAndClearsTheVolatileGuess() {
        var transcript = TranscriptAccumulator()
        transcript.apply("hello wor", isFinal: false)
        transcript.apply("hello world. ", isFinal: true)
        XCTAssertEqual(transcript.text, "hello world. ")
        XCTAssertEqual(transcript.volatile, "")
    }

    func testFinalAndVolatileAreConcatenated() {
        var transcript = TranscriptAccumulator()
        transcript.apply("你好。", isFinal: true)
        transcript.apply("今天", isFinal: false)
        XCTAssertEqual(transcript.text, "你好。今天")
        transcript.apply("今天天气", isFinal: false)
        transcript.apply("今天天气很好。", isFinal: true)
        XCTAssertEqual(transcript.text, "你好。今天天气很好。")
    }

    func testEmptyByDefault() {
        XCTAssertEqual(TranscriptAccumulator().text, "")
    }
}
