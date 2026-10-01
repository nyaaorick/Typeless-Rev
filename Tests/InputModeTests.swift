import XCTest

final class InputModeTests: XCTestCase {
    func testToggleAlternates() {
        var mode = InputMode.english
        mode.toggle()
        XCTAssertEqual(mode, .chinese)
        mode.toggle()
        XCTAssertEqual(mode, .english)
    }

    func testAnnouncementsNameTheModeSwitchedTo() {
        XCTAssertEqual(InputMode.chinese.announcement, "Switch to Chinese mode")
        XCTAssertEqual(InputMode.english.announcement, "Switch to English mode")
    }

    func testQuickReleaseIsATap() {
        var key = ModeKeyClassifier()
        key.press(at: 10)
        XCTAssertNil(key.held(at: 10.2))
        XCTAssertEqual(key.release(at: 10.3), .tap)
        XCTAssertFalse(key.isTracking)
    }

    func testHoldFiresLongPressOnceAndReleaseAddsNothing() {
        var key = ModeKeyClassifier()
        key.press(at: 10)
        XCTAssertNil(key.held(at: 10.49))
        XCTAssertEqual(key.held(at: 10.5), .longPress)
        XCTAssertNil(key.held(at: 11))
        XCTAssertNil(key.release(at: 11.2))
        XCTAssertFalse(key.isTracking)
    }

    func testReleaseAfterTheThresholdWithoutAPollIsStillALongPress() {
        var key = ModeKeyClassifier()
        key.press(at: 10)
        XCTAssertEqual(key.release(at: 10.8), .longPress)
    }

    func testReleaseWithoutAPressIsIgnored() {
        var key = ModeKeyClassifier()
        XCTAssertNil(key.release(at: 10))
        XCTAssertNil(key.held(at: 11))
    }

    func testResetForgetsAHeldKey() {
        var key = ModeKeyClassifier()
        key.press(at: 10)
        key.reset()
        XCTAssertNil(key.held(at: 12))
        XCTAssertNil(key.release(at: 12))
    }

    func testAGestureAfterALongPressStartsClean() {
        var key = ModeKeyClassifier()
        key.press(at: 10)
        XCTAssertEqual(key.held(at: 10.6), .longPress)
        XCTAssertNil(key.release(at: 10.7))
        key.press(at: 20)
        XCTAssertEqual(key.release(at: 20.1), .tap)
    }
}
