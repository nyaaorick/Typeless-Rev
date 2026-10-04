import XCTest

final class DictationContextTests: XCTestCase {
    func testTrimsToTheTextNearestTheCursor() {
        let context = DictationContext(
            style: .plain, before: String(repeating: "a", count: 250) + "B", after: "C" + String(repeating: "d", count: 50),
            source: .field)
        XCTAssertEqual(context.before?.count, DictationContext.beforeLimit)
        XCTAssertEqual(context.before?.last, "B")
        XCTAssertEqual(context.after?.count, DictationContext.afterLimit)
        XCTAssertEqual(context.after?.first, "C")
    }

    func testEmptyIsNil() {
        let context = DictationContext(style: .plain, before: "", after: "", source: .field)
        XCTAssertNil(context.before)
        XCTAssertNil(context.after)
    }

    func testDropsAHalfSurrogateAtTheEdge() {
        let context = DictationContext(style: .plain, before: "\u{FFFD}hi", after: "yo\u{FFFD}", source: .field)
        XCTAssertEqual(context.before, "hi")
        XCTAssertEqual(context.after, "yo")
    }

    func testAppStyles() {
        XCTAssertEqual(AppStyle.forApp("com.tinyspeck.slackmacgap"), .chat)
        XCTAssertEqual(AppStyle.forApp("com.apple.mail"), .document)
        XCTAssertEqual(AppStyle.forApp("com.apple.Terminal"), .code)
        XCTAssertEqual(AppStyle.forApp("com.jetbrains.intellij"), .code)
        XCTAssertEqual(AppStyle.forApp("com.apple.Safari"), .plain)
        XCTAssertEqual(AppStyle.forApp(nil), .plain)
        XCTAssertNil(AppStyle.plain.hint)
    }
}
