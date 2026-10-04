import XCTest

final class RecentCommitTests: XCTestCase {
    private func context(_ before: String?, _ after: String? = nil) -> DictationContext {
        DictationContext(style: .plain, before: before, after: after, source: .field)
    }

    func testEmptyRecordHasNoContext() {
        XCTAssertNil(RecentCommit().context(style: .plain, currentCaret: 0))
    }

    func testRunsContinueFromWhatPrecededTheCursor() {
        var recent = RecentCommit()
        recent.record("Hello.", context: context("Intro: "), caretAfter: 13)
        recent.record(" World.", context: recent.context(style: .plain, currentCaret: 13), caretAfter: 20)
        let next = recent.context(style: .chat, currentCaret: 20)
        XCTAssertEqual(next?.before, "Intro: Hello. World.")
        XCTAssertEqual(next?.source, .ledger)
        XCTAssertEqual(next?.style, .chat)
    }

    func testKeepsWhatFollowedTheCursor() {
        var recent = RecentCommit()
        recent.record("a", context: context(nil, "tail"), caretAfter: 1)
        XCTAssertEqual(recent.context(style: .plain, currentCaret: 1)?.after, "tail")
    }

    func testOnlyTheEndIsKept() {
        var recent = RecentCommit()
        recent.record(String(repeating: "x", count: 300) + "end", context: nil, caretAfter: nil)
        let before = recent.context(style: .plain, currentCaret: nil)?.before
        XCTAssertEqual(before?.count, DictationContext.beforeLimit)
        XCTAssertEqual(before?.hasSuffix("end"), true)
    }

    func testAMovedCursorDropsTheRecord() {
        var recent = RecentCommit()
        recent.record("Hello.", context: nil, caretAfter: 6)
        XCTAssertNil(recent.context(style: .plain, currentCaret: 2))
    }

    func testAnUnknownCursorIsTakenAsUnmoved() {
        var recent = RecentCommit()
        recent.record("Hello.", context: nil, caretAfter: nil)
        XCTAssertEqual(recent.context(style: .plain, currentCaret: 2)?.before, "Hello.")
        recent.record("Hello.", context: nil, caretAfter: 6)
        XCTAssertEqual(recent.context(style: .plain, currentCaret: nil)?.before, "Hello.")
    }

    func testInvalidateClearsIt() {
        var recent = RecentCommit()
        recent.record("Hello.", context: nil, caretAfter: 6)
        recent.invalidate()
        XCTAssertNil(recent.context(style: .plain, currentCaret: 6))
    }
}
