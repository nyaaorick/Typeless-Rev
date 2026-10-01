import XCTest

final class CrashCounterTests: XCTestCase {
    func testOneDeadRunIsForgiven() {
        var counter = CrashCounter()
        XCTAssertFalse(counter.previousRunDied())
        XCTAssertEqual(counter.consecutive, 1)
    }

    func testTwoDeadRunsInARowSwitchPolishOff() {
        var counter = CrashCounter()
        XCTAssertFalse(counter.previousRunDied())
        XCTAssertTrue(counter.previousRunDied())
    }

    func testASuccessfulPolishResetsTheCount() {
        var counter = CrashCounter(consecutive: 1)
        counter.runSucceeded()
        XCTAssertEqual(counter.consecutive, 0)
        XCTAssertFalse(counter.previousRunDied())
    }

    func testNegativeStoredValuesAreClamped() {
        XCTAssertEqual(CrashCounter(consecutive: -3).consecutive, 0)
    }
}
