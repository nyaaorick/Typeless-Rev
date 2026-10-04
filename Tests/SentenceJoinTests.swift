import XCTest

final class SentenceJoinTests: XCTestCase {
    func testLowercasesAFunctionWordMidSentence() {
        XCTAssertEqual(
            SentenceJoin.fitted("And she agreed.", before: "The meeting went well, ", after: nil), "and she agreed.")
        XCTAssertEqual(SentenceJoin.fitted("The draft is ready.", before: "I think", after: nil), "the draft is ready.")
    }

    func testLeavesNamesAndAcronymsAlone() {
        XCTAssertEqual(SentenceJoin.fitted("Joanna agreed.", before: "and then, ", after: nil), "Joanna agreed.")
        XCTAssertEqual(SentenceJoin.fitted("I agreed.", before: "and then, ", after: nil), "I agreed.")
        XCTAssertEqual(SentenceJoin.fitted("IT signed off.", before: "and then, ", after: nil), "IT signed off.")
    }

    func testKeepsTheCapitalAfterASentenceEnds() {
        XCTAssertEqual(SentenceJoin.fitted("And she agreed.", before: "It went well. ", after: nil), "And she agreed.")
        XCTAssertEqual(SentenceJoin.fitted("And she agreed.", before: nil, after: nil), "And she agreed.")
        XCTAssertEqual(SentenceJoin.fitted("And she agreed.", before: "会议很顺利", after: nil), "And she agreed.")
    }

    func testDropsTheClosingPeriodWhenTheSentenceGoesOn() {
        XCTAssertEqual(SentenceJoin.fitted("Very quick.", before: nil, after: "brown fox"), "Very quick")
        XCTAssertEqual(SentenceJoin.fitted("Very quick.", before: nil, after: "Brown"), "Very quick.")
        XCTAssertEqual(SentenceJoin.fitted("Wait...", before: nil, after: "and"), "Wait...")
        XCTAssertEqual(SentenceJoin.fitted("Really?", before: nil, after: "and"), "Really?")
    }
}
