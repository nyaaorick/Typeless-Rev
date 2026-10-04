import AppKit
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

    /// Option plus device bits: 0x40 is the right key, 0x20 the left one.
    private func option(_ deviceBits: UInt) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | deviceBits)
    }

    func testReleaseWithLeftTwinStillHeld() {
        var detector = PushToTalkDetector(key: .rightOption)
        XCTAssertEqual(detector.flagsChanged(keyCode: 61, flags: option(0x40)), .press)
        // Left Option goes down while the right one is held: not ours.
        XCTAssertNil(detector.flagsChanged(keyCode: 58, flags: option(0x60)))
        // Releasing the right key leaves the Option flag set by the left key.
        XCTAssertEqual(detector.flagsChanged(keyCode: 61, flags: option(0x20)), .release)
        XCTAssertFalse(detector.isDown)
    }

    /// SunBrowser delivers the press twice; the copy must not end the dictation.
    func testDuplicatePressIsNotARelease() {
        var detector = PushToTalkDetector(key: .rightOption)
        XCTAssertEqual(detector.flagsChanged(keyCode: 61, flags: option(0x40)), .press)
        XCTAssertNil(detector.flagsChanged(keyCode: 61, flags: option(0x40)))
        XCTAssertTrue(detector.isDown)
        XCTAssertEqual(detector.flagsChanged(keyCode: 61, flags: []), .release)
    }

    func testDuplicatePressWithoutDeviceBitsIsNotARelease() {
        var detector = PushToTalkDetector(key: .rightOption)
        XCTAssertEqual(detector.flagsChanged(keyCode: 61, flags: .option), .press)
        XCTAssertNil(detector.flagsChanged(keyCode: 61, flags: .option))
        XCTAssertEqual(detector.flagsChanged(keyCode: 61, flags: []), .release)
    }

    func testRightControlAndCommandUseTheirOwnBits() {
        var control = PushToTalkDetector(key: .rightControl)
        let rightControl = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.control.rawValue | 0x2000)
        XCTAssertEqual(control.flagsChanged(keyCode: 62, flags: rightControl), .press)
        XCTAssertEqual(control.flagsChanged(keyCode: 62, flags: NSEvent.ModifierFlags(rawValue: 0x100)), .release)
        var command = PushToTalkDetector(key: .rightCommand)
        let rightCommand = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x10)
        XCTAssertEqual(command.flagsChanged(keyCode: 54, flags: rightCommand), .press)
        XCTAssertNil(command.flagsChanged(keyCode: 54, flags: rightCommand))
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
