import AppKit
import XCTest

final class CapsLockGuardTests: XCTestCase {
    func testEveryPressSwitchesLanguage() {
        let caps = CapsLockGuard()
        XCTAssertEqual(caps.press(shift: false, at: 1), .switchLanguage)
        XCTAssertEqual(caps.press(shift: false, at: 2), .switchLanguage)
        XCTAssertEqual(caps.press(shift: false, at: 3), .switchLanguage)
    }

    /// Seen on 2026-10-04: the same event arrived twice, 5 to 37 ms apart.
    func testDuplicateEventIsOnePress() {
        let caps = CapsLockGuard()
        XCTAssertEqual(caps.press(shift: false, at: 1), .switchLanguage)
        XCTAssertNil(caps.press(shift: false, at: 1.037))
        XCTAssertEqual(caps.press(shift: false, at: 1.5), .switchLanguage)
    }

    func testShiftTurnsCapsLockOnAndOff() {
        let caps = CapsLockGuard()
        XCTAssertEqual(caps.press(shift: true, at: 1), .capsLockOn)
        XCTAssertTrue(caps.isOn)
        XCTAssertEqual(caps.press(shift: true, at: 2), .capsLockOff)
        XCTAssertFalse(caps.isOn)
    }

    func testKeyAloneTurnsCapsLockOffBeforeSwitching() {
        let caps = CapsLockGuard()
        _ = caps.press(shift: true, at: 1)
        XCTAssertEqual(caps.press(shift: false, at: 2), .capsLockOff)
        XCTAssertEqual(caps.press(shift: false, at: 3), .switchLanguage)
    }

    func testLettersPassThroughWhenNothingIsLocked() {
        XCTAssertNil(CapsLockGuard().englishText("a", flags: []))
        XCTAssertNil(CapsLockGuard().englishText("A", flags: .shift))
    }

    /// The real lock is left on by every other press; it must not give capitals.
    func testRealLockAloneTypesLowerCase() {
        let caps = CapsLockGuard()
        XCTAssertEqual(caps.englishText("A", flags: .capsLock), "a")
        XCTAssertEqual(caps.englishText("A", flags: [.capsLock, .shift]), "A")
    }

    func testCapsLockTypesCapitalsAndShiftFlipsThem() {
        let caps = CapsLockGuard()
        _ = caps.press(shift: true, at: 1)
        XCTAssertEqual(caps.englishText("a", flags: []), "A")
        XCTAssertEqual(caps.englishText("a", flags: .capsLock), "A")
        XCTAssertEqual(caps.englishText("A", flags: .shift), "a")
    }

    func testShortcutsAndNonLettersGoToTheApp() {
        let caps = CapsLockGuard()
        _ = caps.press(shift: true, at: 1)
        XCTAssertNil(caps.englishText("c", flags: [.command]))
        XCTAssertNil(caps.englishText("a", flags: [.option]))
        XCTAssertNil(caps.englishText("1", flags: []))
        XCTAssertNil(caps.englishText("/", flags: [.capsLock]))
        XCTAssertNil(caps.englishText(nil, flags: [.capsLock]))
    }
}
