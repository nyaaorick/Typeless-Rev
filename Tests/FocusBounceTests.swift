import XCTest

final class FocusBounceTests: XCTestCase {
    func testFirstActivationStartsInEnglish() {
        var focus = FocusBounce()
        XCTAssertEqual(focus.modeOnActivation(current: .chinese, at: 10), .english)
    }

    /// Control Center took input for 21 ms on 2026-10-04 and Chinese was lost.
    func testBounceKeepsChinese() {
        var focus = FocusBounce()
        focus.deactivated(at: 36.550)
        XCTAssertEqual(focus.modeOnActivation(current: .chinese, at: 36.571), .chinese)
    }

    func testComingBackLaterStartsInEnglish() {
        var focus = FocusBounce()
        focus.deactivated(at: 10)
        XCTAssertEqual(focus.modeOnActivation(current: .chinese, at: 10 + FocusBounce.window), .english)
    }

    func testABounceIsUsedOnce() {
        var focus = FocusBounce()
        focus.deactivated(at: 10)
        XCTAssertEqual(focus.modeOnActivation(current: .chinese, at: 10.1), .chinese)
        // Activated again without losing focus in between: a fresh start.
        XCTAssertEqual(focus.modeOnActivation(current: .chinese, at: 10.2), .english)
    }

    func testEnglishStaysEnglish() {
        var focus = FocusBounce()
        focus.deactivated(at: 10)
        XCTAssertEqual(focus.modeOnActivation(current: .english, at: 10.1), .english)
    }
}
