import XCTest

final class TextOffsetsTests: XCTestCase {
    func testASCIIOffsetsAreIdentity() {
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 0, in: "ni hao"), 0)
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 3, in: "ni hao"), 3)
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 6, in: "ni hao"), 6)
    }

    func testCJKIsThreeBytesButOneUTF16Unit() {
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 3, in: "你好"), 1)
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 6, in: "你好"), 2)
    }

    func testAstralCharactersAreTwoUTF16Units() {
        let s = "a😀b"  // bytes: a(1) 😀(4) b(1)
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 1, in: s), 1)
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 5, in: s), 3)
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 6, in: s), 4)
    }

    func testOffsetInsideACharacterRoundsDown() {
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 2, in: "你好"), 0)
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 4, in: "你好"), 1)
    }

    func testOutOfRangeOffsetsAreClamped() {
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: -5, in: "abc"), 0)
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 99, in: "abc"), 3)
        XCTAssertEqual(TextOffsets.utf16Offset(forUTF8Offset: 0, in: ""), 0)
    }
}
