import XCTest

final class PushToTalkTests: XCTestCase {
    func testPressAndRelease() {
        var detector = PushToTalkDetector(key: .rightOption)
        XCTAssertEqual(detector.flagsChanged(keyCode: 61, flags: .option), .press)
        XCTAssertTrue(detector.isDown)
        XCTAssertEqual(detector.flagsChanged(keyCode: 61, flags: []), .release)
        XCTAssertFalse(detector.isDown)
    }

    func testOtherModifiersAreIgnored() {
        var detector = PushToTalkDetector(key: .rightOption)
        XCTAssertNil(detector.flagsChanged(keyCode: 58, flags: .option))  // left Option
        XCTAssertNil(detector.flagsChanged(keyCode: 56, flags: .shift))
        XCTAssertFalse(detector.isDown)
    }

    func testReleaseWithLeftTwinStillHeld() {
        var detector = PushToTalkDetector(key: .rightOption)
        XCTAssertEqual(detector.flagsChanged(keyCode: 61, flags: .option), .press)
        // Left Option goes down and up while the right one is held: not ours.
        XCTAssertNil(detector.flagsChanged(keyCode: 58, flags: .option))
        // Releasing the right key leaves the Option flag set by the left key.
        XCTAssertEqual(detector.flagsChanged(keyCode: 61, flags: .option), .release)
        XCTAssertFalse(detector.isDown)
    }

    func testSpuriousReleaseWithoutPressIsIgnored() {
        var detector = PushToTalkDetector(key: .rightOption)
        XCTAssertNil(detector.flagsChanged(keyCode: 61, flags: []))
        XCTAssertFalse(detector.isDown)
    }

    func testResetForgetsAHeldKey() {
        var detector = PushToTalkDetector(key: .rightControl)
        XCTAssertEqual(detector.flagsChanged(keyCode: 62, flags: .control), .press)
        detector.reset()
        XCTAssertEqual(detector.flagsChanged(keyCode: 62, flags: .control), .press)
    }

    func testEveryKeyHasADistinctKeyCode() {
        XCTAssertEqual(Set(PushToTalkKey.allCases.map(\.keyCode)).count, PushToTalkKey.allCases.count)
    }
}
