import XCTest
@testable import QuietNest

final class AudioCoreTests: XCTestCase {

    func testXoshiroIsDeterministicForSameSeed() {
        var lhs = Xoshiro256(seed: 123_456)
        var rhs = Xoshiro256(seed: 123_456)

        for _ in 0..<64 {
            XCTAssertEqual(lhs.nextUInt64(), rhs.nextUInt64())
        }
    }

    func testXoshiroGeneratesValuesWithinRequestedRanges() {
        var rng = Xoshiro256(seed: 42)

        for _ in 0..<500 {
            let intVal = rng.nextInt(in: 3...9)
            XCTAssertGreaterThanOrEqual(intVal, 3)
            XCTAssertLessThanOrEqual(intVal, 9)

            let floatVal = rng.nextFloat(in: 0.2...0.8)
            XCTAssertGreaterThanOrEqual(floatVal, 0.2)
            XCTAssertLessThanOrEqual(floatVal, 0.8)
        }
    }

    func testParamSmootherConvergesToTargetMonotonically() {
        var smoother = ParamSmoother(initial: 0, smoothTimeMs: 10, sampleRate: 1_000)
        smoother.setTarget(1)

        var previous: Float = 0
        for _ in 0..<200 {
            let current = smoother.next()
            XCTAssertGreaterThanOrEqual(current, previous)
            XCTAssertLessThanOrEqual(current, 1.0)
            previous = current
        }

        XCTAssertTrue(smoother.isSettled)
        XCTAssertEqual(smoother.value, 1.0, accuracy: 0.001)
    }

    func testParamSmootherSnapJumpsToTarget() {
        var smoother = ParamSmoother(initial: 0.3)
        smoother.setTarget(0.9)
        _ = smoother.next()
        XCTAssertNotEqual(smoother.value, 0.9)

        smoother.snap()
        XCTAssertEqual(smoother.value, 0.9, accuracy: 0.0001)
        XCTAssertTrue(smoother.isSettled)
    }
}
