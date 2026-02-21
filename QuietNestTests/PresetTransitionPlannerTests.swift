import XCTest
@testable import QuietNest

final class PresetTransitionPlannerTests: XCTestCase {

    func testSanitizeTracksTrimsDedupsClampsAndLimits() {
        let input: [(name: String, volume: Double)] = [
            (" 雨声 ", 1.3),
            ("雨声", 0.2),
            (" ", 0.5),
            ("篝火", -0.1),
            ("钟摆", 0.3),
            ("海浪", 0.4),
            ("微风", 0.5),
            ("鸟鸣", 0.6),
            ("蛙鸣", 0.7),
            ("蟋蟀", 0.8)
        ]

        let sanitized = PresetTransitionPlanner.sanitizeTracks(input, maxTracks: 8)

        XCTAssertEqual(sanitized.count, 8)
        XCTAssertEqual(sanitized[0].name, "雨声")
        XCTAssertEqual(sanitized[0].volume, 1.0, accuracy: 0.0001)
        XCTAssertEqual(sanitized[1].name, "篝火")
        XCTAssertEqual(sanitized[1].volume, 0.0, accuracy: 0.0001)
        XCTAssertFalse(sanitized.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testPrepareTracksAppliesRmsAttenuationOnly() {
        let tracks: [(name: String, volume: Double)] = [
            ("雨声", 0.7),
            ("篝火", 0.4),
            ("钟摆", 0.3),
        ]
        let target = ["雨夜书房": 0.8]

        let prepared = PresetTransitionPlanner.prepareTracks(
            tracks,
            sceneName: "雨夜书房",
            sceneTargetRMS: target
        )
        XCTAssertLessThan(prepared[0].volume, tracks[0].volume)

        let softTracks: [(name: String, volume: Double)] = [("微风", 0.2), ("猫咪", 0.1)]
        let softPrepared = PresetTransitionPlanner.prepareTracks(
            softTracks,
            sceneName: "雨夜书房",
            sceneTargetRMS: target
        )
        XCTAssertEqual(softPrepared[0].volume, 0.2, accuracy: 0.0001)
        XCTAssertEqual(softPrepared[1].volume, 0.1, accuracy: 0.0001)
    }

    func testHasMeaningfulDifferenceDetectsTrackAndVolumeChanges() {
        let a: [(name: String, volume: Double)] = [("雨声", 0.7), ("篝火", 0.4)]
        let b: [(name: String, volume: Double)] = [("雨声", 0.7005), ("篝火", 0.4)]
        let c: [(name: String, volume: Double)] = [("雨声", 0.72), ("篝火", 0.4)]
        let d: [(name: String, volume: Double)] = [("篝火", 0.4), ("雨声", 0.7)]

        XCTAssertFalse(PresetTransitionPlanner.hasMeaningfulDifference(current: a, target: b))
        XCTAssertTrue(PresetTransitionPlanner.hasMeaningfulDifference(current: a, target: c))
        XCTAssertTrue(PresetTransitionPlanner.hasMeaningfulDifference(current: a, target: d))
    }
}
