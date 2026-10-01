import XCTest

final class AudioLevelTests: XCTestCase {
    func testSilenceIsEmpty() {
        XCTAssertEqual(AudioLevel.meter(rms: 0), 0)
        XCTAssertEqual(AudioLevel.meter(rms: 0.0001), 0)  // -80 dBFS
    }

    func testLoudSoundsFillTheMeter() {
        XCTAssertEqual(AudioLevel.meter(rms: 1), 1)
        XCTAssertEqual(AudioLevel.meter(rms: 0.5), 1)  // -6 dBFS
    }

    func testSpeechLevelsLandInTheMiddle() {
        let level = AudioLevel.meter(rms: 0.04)  // about -28 dBFS
        XCTAssertGreaterThan(level, 0.3)
        XCTAssertLessThan(level, 0.8)
    }

    func testMeterRisesWithAmplitude() {
        XCTAssertLessThan(AudioLevel.meter(rms: 0.01), AudioLevel.meter(rms: 0.05))
        XCTAssertLessThan(AudioLevel.meter(rms: 0.05), AudioLevel.meter(rms: 0.2))
    }

    func testRMSOfASquareWave() {
        let samples: [Float] = [0.5, -0.5, 0.5, -0.5]
        XCTAssertEqual(samples.withUnsafeBufferPointer { AudioLevel.rms($0) }, 0.5, accuracy: 1e-6)
        XCTAssertEqual([Float]().withUnsafeBufferPointer { AudioLevel.rms($0) }, 0)
    }
}
