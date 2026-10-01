import XCTest

final class SeedPolicyTests: XCTestCase {
    private let bundled = "\(SeedPolicy.managedMarker)\npatch:\n  a: 2\n"

    func testMissingFileIsInstalled() {
        XCTAssertTrue(SeedPolicy.shouldInstall(existing: nil, bundled: bundled))
    }

    func testStaleManagedFileIsRefreshed() {
        let old = "\(SeedPolicy.managedMarker)\npatch:\n  a: 1\n"
        XCTAssertTrue(SeedPolicy.shouldInstall(existing: old, bundled: bundled))
    }

    func testCurrentManagedFileIsLeftAlone() {
        XCTAssertFalse(SeedPolicy.shouldInstall(existing: bundled, bundled: bundled))
    }

    func testFileWithoutTheMarkerIsTheUsersOwn() {
        XCTAssertFalse(SeedPolicy.shouldInstall(existing: "patch:\n  a: 1\n", bundled: bundled))
        // Deleting the marker line, but leaving it further down, does not count.
        XCTAssertFalse(SeedPolicy.shouldInstall(existing: "patch:\n\(SeedPolicy.managedMarker)\n", bundled: bundled))
    }

    func testUneditedFirstReleaseFileIsMigrated() {
        XCTAssertTrue(SeedPolicy.shouldInstall(existing: SeedPolicy.legacyDefaultCustom, bundled: bundled))
        XCTAssertFalse(SeedPolicy.shouldInstall(existing: SeedPolicy.legacyDefaultCustom + "# mine\n", bundled: bundled))
    }

    func testMarkerToleratesTrailingSpaces() {
        XCTAssertTrue(SeedPolicy.isManaged("\(SeedPolicy.managedMarker)  \nx"))
    }
}
