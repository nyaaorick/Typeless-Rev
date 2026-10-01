import XCTest

final class PermissionStatusTests: XCTestCase {
    func testTitlesNameThePermissionAndItsState() {
        XCTAssertEqual(PermissionStatus.allowed.menuTitle("Microphone"), "Microphone: Allowed")
        XCTAssertEqual(PermissionStatus.denied.menuTitle("Microphone"), "Microphone: Off")
        XCTAssertEqual(PermissionStatus.notDetermined.menuTitle("Microphone"), "Microphone: Not Asked Yet")
        XCTAssertEqual(PermissionStatus.restricted.menuTitle("Microphone"), "Microphone: Restricted")
    }

    func testOnlyAskingOrDeniedHasAnAction() {
        XCTAssertNotNil(PermissionStatus.notDetermined.actionTitle)
        XCTAssertNotNil(PermissionStatus.denied.actionTitle)
        XCTAssertNil(PermissionStatus.allowed.actionTitle)
        XCTAssertNil(PermissionStatus.restricted.actionTitle)
    }
}
