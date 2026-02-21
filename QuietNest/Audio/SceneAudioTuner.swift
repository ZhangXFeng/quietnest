import Foundation

/// 每种声音的粒子合成参数集合
struct GrainPreset {
    let density: Float
    let lenMs: ClosedRange<Float>
    let pitch: ClosedRange<Float>
    let pan: ClosedRange<Float>
}

struct SceneGrainTuning {
    let densityScale: Float
    let lengthScale: Float
    let pitchScale: Float
    let panScale: Float
}

enum SceneAudioTuner {

    static func adjustedGain(
        soundId: String,
        uiGain: Float,
        loudnessTrim: [String: Float]
    ) -> Float {
        let trim = loudnessTrim[soundId] ?? 1.0
        return clamp(uiGain * trim, min: 0, max: 1)
    }

    static func sceneAdjustedPreset(
        basePreset: GrainPreset,
        soundId: String,
        sceneName: String,
        sceneGranularTuning: [String: [String: SceneGrainTuning]]
    ) -> GrainPreset {
        guard let sceneMap = sceneGranularTuning[sceneName],
              let tuning = sceneMap[soundId] else {
            return basePreset
        }
        return apply(tuning: tuning, to: basePreset)
    }

    static func normalizeVolumes(
        _ tracks: [(name: String, volume: Double)],
        sceneName: String,
        sceneTargetRMS: [String: Double],
        defaultTargetRMS: Double = 0.85
    ) -> [(name: String, volume: Double)] {
        guard !tracks.isEmpty else { return tracks }

        let power = tracks.reduce(0.0) { partial, track in
            partial + track.volume * track.volume
        }
        let rms = sqrt(max(power, 0.0001))
        let target = sceneTargetRMS[sceneName] ?? defaultTargetRMS
        let scale = min(1.0, target / rms)
        guard scale < 0.999 else { return tracks }

        return tracks.map { track in
            (name: track.name, volume: max(0.0, min(1.0, track.volume * scale)))
        }
    }

    private static func apply(tuning: SceneGrainTuning, to preset: GrainPreset) -> GrainPreset {
        let density = clamp(preset.density * tuning.densityScale, min: 0.1, max: 1.0)
        let len = scaleRange(preset.lenMs, by: tuning.lengthScale, min: 12, max: 1000)
        let pitch = scaleRange(preset.pitch, by: tuning.pitchScale, min: -1.0, max: 1.0)
        let pan = scaleRange(preset.pan, by: tuning.panScale, min: -0.5, max: 0.5)
        return GrainPreset(density: density, lenMs: len, pitch: pitch, pan: pan)
    }

    private static func scaleRange(
        _ range: ClosedRange<Float>,
        by scale: Float,
        min minValue: Float,
        max maxValue: Float
    ) -> ClosedRange<Float> {
        let lower = clamp(range.lowerBound * scale, min: minValue, max: maxValue)
        let upper = clamp(range.upperBound * scale, min: minValue, max: maxValue)
        return Swift.min(lower, upper)...Swift.max(lower, upper)
    }

    private static func clamp(_ value: Float, min: Float, max: Float) -> Float {
        Swift.min(Swift.max(value, min), max)
    }
}
