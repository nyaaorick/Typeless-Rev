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
}
