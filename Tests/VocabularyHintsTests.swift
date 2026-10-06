import XCTest

final class VocabularyHintsTests: XCTestCase {
    func testKeepsIdentifiersWhole() {
        let words = VocabularyHints.keywords(in: "open VoiceSession.swift and call setUp on speech_locale-2")
        XCTAssertTrue(words.contains("VoiceSession.swift"))
        XCTAssertTrue(words.contains("setUp"))
        XCTAssertTrue(words.contains("speech_locale-2"))
    }

    func testDropsStopwordsAndShortWords() {
        XCTAssertEqual(VocabularyHints.keywords(in: "I think that we should run it"), [])
    }

    func testKeepsAcronymsAndCapitalizedNames() {
        let words = VocabularyHints.keywords(in: "ask Bob about the LLM and the UI")
        XCTAssertEqual(Set(words), ["Bob", "LLM", "UI"])
    }

    func testMostRecentFirstWithoutDuplicates() {
        XCTAssertEqual(
            VocabularyHints.keywords(in: "pipeline polish Pipeline model"), ["model", "Pipeline", "polish"])
    }

    func testTrailingPunctuationIsNotPartOfAWord() {
        XCTAssertEqual(VocabularyHints.keywords(in: "check the pipeline."), ["pipeline", "check"])
    }

    func testCapsWordsFromTheField() {
        let text = (1...100).map { "word\($0)" }.joined(separator: " ")
        let words = VocabularyHints.keywords(in: text)
        XCTAssertEqual(words.count, VocabularyHints.fieldLimit)
        XCTAssertEqual(words.first, "word100")
    }

    func testNoFieldGivesTheFixedVocabulary() {
        XCTAssertEqual(VocabularyHints.terms(before: nil, style: .plain), VocabularyHints.general)
        XCTAssertEqual(VocabularyHints.terms(before: "我们周三开会", style: .plain), VocabularyHints.general)
    }

    func testCodeStyleAddsCodeTerms() {
        let terms = VocabularyHints.terms(before: nil, style: .code)
        XCTAssertTrue(terms.contains("commit"))
        XCTAssertFalse(VocabularyHints.terms(before: nil, style: .chat).contains("commit"))
    }

    func testFieldWordsComeFirstAndDuplicatesIgnoreCase() {
        let terms = VocabularyHints.terms(before: "the PIPELINE is slow", style: .plain)
        XCTAssertEqual(terms.first, "slow")
        XCTAssertEqual(terms.filter { $0.lowercased() == "pipeline" }, ["PIPELINE"])
    }

    func testTotalIsCapped() {
        let text = (1...100).map { "word\($0)" }.joined(separator: " ")
        XCTAssertLessThanOrEqual(VocabularyHints.terms(before: text, style: .code).count, VocabularyHints.limit)
    }
}
