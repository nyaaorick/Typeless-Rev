import XCTest

final class MemoryTierTests: XCTestCase {
    func testStartsAtZero() {
        var tracker = MemoryTierTracker()
        tracker.update(.normal, at: 0)
        XCTAssertEqual(tracker.tier, 0)
    }

    func testWarningGivesOneThenTwoAfterItLasts() {
        var tracker = MemoryTierTracker()
        tracker.update(.warning, at: 100)
        XCTAssertEqual(tracker.tier, 1)
        tracker.tick(at: 129)
        XCTAssertEqual(tracker.tier, 1)
        tracker.tick(at: 130)
        XCTAssertEqual(tracker.tier, 2)
    }

    func testCriticalJumpsToThree() {
        var tracker = MemoryTierTracker()
        tracker.update(.critical, at: 5)
        XCTAssertEqual(tracker.tier, 3)
    }

    func testFallingBackToWarningDoesNotLowerTheTier() {
        var tracker = MemoryTierTracker()
        tracker.update(.critical, at: 0)
        tracker.update(.warning, at: 10)
        XCTAssertEqual(tracker.tier, 3)
    }

    func testRecoversOnlyAfterNormalLasts() {
        var tracker = MemoryTierTracker()
        tracker.update(.warning, at: 0)
        tracker.tick(at: 40)
        tracker.update(.normal, at: 50)
        XCTAssertEqual(tracker.tier, 2)
        tracker.tick(at: 139)
        XCTAssertEqual(tracker.tier, 2)
        tracker.tick(at: 140)
        XCTAssertEqual(tracker.tier, 0)
    }

    func testABriefDipKeepsTheTier() {
        var tracker = MemoryTierTracker()
        tracker.update(.warning, at: 0)
        tracker.update(.normal, at: 10)
        tracker.update(.warning, at: 20)
        XCTAssertEqual(tracker.tier, 1)
    }

    func testCanLoadKeepsAReserve() {
        let total: Int64 = 16_000_000_000
        // 44% of 16 GB free is 7.04 GB: a 5.3 GB model leaves 1.74 GB, above the 0.8 GB reserve.
        XCTAssertTrue(MemoryBudget.canLoad(bytes: 5_300_000_000, freePercent: 44, totalBytes: total))
        // 30% free is 4.8 GB: not enough for it.
        XCTAssertFalse(MemoryBudget.canLoad(bytes: 5_300_000_000, freePercent: 30, totalBytes: total))
        XCTAssertTrue(MemoryBudget.canLoad(bytes: 0, freePercent: 5, totalBytes: total))
        XCTAssertFalse(MemoryBudget.canLoad(bytes: 1, freePercent: 5, totalBytes: total))
    }
}
