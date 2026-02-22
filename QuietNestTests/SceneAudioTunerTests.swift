import XCTest
@testable import QuietNest

final class SceneAudioTunerTests: XCTestCase {

    func testAdjustedGainAppliesTrimAndClamps() {
        let trim: [String: Float] = ["rain": 0.8, "boost": 2.0]

        let normal = SceneAudioTuner.adjustedGain(soundId: "rain", uiGain: 0.5, loudnessTrim: trim)
        XCTAssertEqual(normal, 0.4, accuracy: 0.0001)

        let clampedHigh = SceneAudioTuner.adjustedGain(soundId: "boost", uiGain: 0.8, loudnessTrim: trim)
        XCTAssertEqual(clampedHigh, 1.0, accuracy: 0.0001)

        let fallback = SceneAudioTuner.adjustedGain(soundId: "unknown", uiGain: 0.6, loudnessTrim: trim)
        XCTAssertEqual(fallback, 0.6, accuracy: 0.0001)
    }

    func testSceneAdjustedPresetUsesSceneSpecificTuning() {
        let base = GrainPreset(
            density: 0.5,
            lenMs: 100...200,
            pitch: -0.4...0.4,
            pan: -0.3...0.3
        )
        let tuning: [String: [String: SceneGrainTuning]] = [
            "雨夜书房": [
                "rain": SceneGrainTuning(
                    densityScale: 1.4,
                    lengthScale: 0.5,
                    pitchScale: 2.0,
                    panScale: 0.4
                )
            ]
        ]

        let adjusted = SceneAudioTuner.sceneAdjustedPreset(
            basePreset: base,
            soundId: "rain",
            sceneName: "雨夜书房",
            sceneGranularTuning: tuning
        )

        XCTAssertEqual(adjusted.density, 0.7, accuracy: 0.0001)
        XCTAssertEqual(adjusted.lenMs.lowerBound, 50, accuracy: 0.0001)
        XCTAssertEqual(adjusted.lenMs.upperBound, 100, accuracy: 0.0001)
        XCTAssertEqual(adjusted.pitch.lowerBound, -0.8, accuracy: 0.0001)
        XCTAssertEqual(adjusted.pitch.upperBound, 0.8, accuracy: 0.0001)
        XCTAssertEqual(adjusted.pan.lowerBound, -0.12, accuracy: 0.0001)
        XCTAssertEqual(adjusted.pan.upperBound, 0.12, accuracy: 0.0001)
    }

    func testNormalizeVolumesOnlyAttenuatesWhenOverTargetRms() {
        let tracks = [("雨声", 0.7), ("篝火", 0.4), ("钟摆", 0.3)]
        let target: [String: Double] = ["雨夜书房": 0.8]

        let normalized = SceneAudioTuner.normalizeVolumes(
            tracks,
            sceneName: "雨夜书房",
            sceneTargetRMS: target
        )

        XCTAssertLessThan(normalized[0].volume, tracks[0].1)
        XCTAssertLessThan(normalized[1].volume, tracks[1].1)
        XCTAssertLessThan(normalized[2].volume, tracks[2].1)

        let softTracks = [("微风", 0.2), ("猫咪", 0.1)]
        let unchanged = SceneAudioTuner.normalizeVolumes(
            softTracks,
            sceneName: "雨夜书房",
            sceneTargetRMS: target
        )
        XCTAssertEqual(unchanged[0].volume, softTracks[0].1, accuracy: 0.0001)
        XCTAssertEqual(unchanged[1].volume, softTracks[1].1, accuracy: 0.0001)
    }
}
