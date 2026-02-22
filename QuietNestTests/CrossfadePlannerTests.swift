import XCTest
@testable import QuietNest

final class CrossfadePlannerTests: XCTestCase {

    func testMakePlanIncreasesDurationForMoreTracks() {
        let low = CrossfadePlanner.makePlan(trackCount: 1)
        let high = CrossfadePlanner.makePlan(trackCount: 8)

        let lowHalfNs = UInt64(low.steps) * low.stepDurationNs
        let highHalfNs = UInt64(high.steps) * high.stepDurationNs

        XCTAssertLessThan(lowHalfNs, highHalfNs)
        XCTAssertGreaterThanOrEqual(low.steps, 8)
        XCTAssertLessThanOrEqual(high.steps, 26)
    }

    func testMakePlanClampsTargetVolume() {
        let low = CrossfadePlanner.makePlan(trackCount: 3, targetVolume: -1)
        let high = CrossfadePlanner.makePlan(trackCount: 3, targetVolume: 2)
        XCTAssertEqual(low.targetVolume, 0, accuracy: 0.0001)
        XCTAssertEqual(high.targetVolume, 1, accuracy: 0.0001)
    }
}
