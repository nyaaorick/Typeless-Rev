import AppKit
import XCTest

final class KeyTranslatorTests: XCTestCase {
    private func key(_ code: UInt16, _ chars: String?, _ flags: NSEvent.ModifierFlags = []) -> RimeKeyEvent? {
        KeyTranslator.keyDown(keyCode: code, charactersIgnoringModifiers: chars, flags: flags)
    }

    func testPlainLetter() {
        XCTAssertEqual(key(0, "a"), RimeKeyEvent(keycode: 0x61, mask: 0))
    }

    func testShiftedLetterIsUppercaseWithShiftMask() {
        XCTAssertEqual(key(0, "A", .shift), RimeKeyEvent(keycode: 0x41, mask: RimeModifier.shift))
    }

    func testCapsLockUppercasesLetters() {
        XCTAssertEqual(key(0, "a", .capsLock), RimeKeyEvent(keycode: 0x41, mask: RimeModifier.lock))
    }

    func testShiftWithCapsLockCancelsOut() {
        XCTAssertEqual(
            key(0, "A", [.shift, .capsLock]),
            RimeKeyEvent(keycode: 0x61, mask: RimeModifier.shift | RimeModifier.lock))
    }

    func testShiftedPunctuationKeepsSymbol() {
        XCTAssertEqual(key(18, "!", .shift), RimeKeyEvent(keycode: 0x21, mask: RimeModifier.shift))
    }

    func testControlCombinationUsesBaseLetter() {
        XCTAssertEqual(key(45, "n", .control), RimeKeyEvent(keycode: 0x6e, mask: RimeModifier.control))
    }

    func testOptionAndCommandMasks() {
        XCTAssertEqual(key(0, "a", [.option, .command])?.mask, RimeModifier.alt | RimeModifier.super)
    }

    func testEditingKeys() {
        XCTAssertEqual(key(36, "\r")?.keycode, 0xff0d)
        XCTAssertEqual(key(51, "\u{7f}")?.keycode, 0xff08)
        XCTAssertEqual(key(53, "\u{1b}")?.keycode, 0xff1b)
        XCTAssertEqual(key(48, "\t")?.keycode, 0xff09)
        XCTAssertEqual(key(49, " ")?.keycode, 0x20)
        XCTAssertEqual(key(117, "\u{F728}")?.keycode, 0xffff)
    }

    func testArrowsAndPaging() {
        XCTAssertEqual(key(123, "\u{F702}")?.keycode, 0xff51)
        XCTAssertEqual(key(126, "\u{F700}")?.keycode, 0xff52)
        XCTAssertEqual(key(124, "\u{F703}")?.keycode, 0xff53)
        XCTAssertEqual(key(125, "\u{F701}")?.keycode, 0xff54)
        XCTAssertEqual(key(116, "\u{F72C}")?.keycode, 0xff55)
        XCTAssertEqual(key(121, "\u{F72D}")?.keycode, 0xff56)
    }

    func testFunctionAndKeypadKeys() {
        XCTAssertEqual(key(122, "\u{F704}")?.keycode, 0xffbe)  // F1
        XCTAssertEqual(key(111, "\u{F70F}")?.keycode, 0xffc9)  // F12
        XCTAssertEqual(key(82, "0")?.keycode, 0xffb0)
        XCTAssertEqual(key(83, "1")?.keycode, 0xffb1)
        XCTAssertEqual(key(92, "9")?.keycode, 0xffb9)
    }

    func testNonLatinCharactersUseUnicodeKeysyms() {
        XCTAssertEqual(key(0, "é")?.keycode, 0xe9)
        XCTAssertEqual(key(0, "中")?.keycode, 0x0100_4e2d)
    }

    func testUnmappedKeysAreIgnored() {
        XCTAssertNil(key(200, "\u{F700}"))  // unknown private-use function key
        XCTAssertNil(key(200, "\u{01}"))  // control character
        XCTAssertNil(key(200, ""))
        XCTAssertNil(key(200, nil))
    }
}
