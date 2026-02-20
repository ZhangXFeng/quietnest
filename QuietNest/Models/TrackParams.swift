import Foundation

/// 轨道类型
enum TrackType: String, Codable {
    case granular   // 粒子合成（真实录音素材）
    case dsp        // DSP 实时生成（噪声类）
}

/// 噪声类型
enum NoiseType: String, Codable, CaseIterable {
    case white
    case pink
    case brown
    case blue
}

/// 轨道参数（用于引擎层）
struct TrackParams {
    let soundId: String
    let type: TrackType
    var gain: Float             // 0...1
    var lpHz: Float             // 低通截止频率 500...16000

    // 粒子合成参数（type == .granular 时使用）
    var grainLenMsMin: Float    // grain 最小长度（ms）
    var grainLenMsMax: Float    // grain 最大长度（ms）
    var density: Float          // 0.1...1.0，控制 grain 重叠密度
    var pitchMin: Float         // 半音偏移下限
    var pitchMax: Float         // 半音偏移上限
    var panMin: Float           // pan 偏移下限
    var panMax: Float           // pan 偏移上限

    // DSP 噪声参数（type == .dsp 时使用）
    var noiseType: NoiseType

    var seed: UInt64

    /// 创建粒子合成轨道参数
    static func granular(
        soundId: String,
        gain: Float = 0.5,
        density: Float = 0.5,
        grainLenMs: ClosedRange<Float> = 80...160,
        pitchRange: ClosedRange<Float> = -0.3...0.3,
        panRange: ClosedRange<Float> = -0.3...0.3,
        lpHz: Float = 10000,
        seed: UInt64 = 0
    ) -> TrackParams {
        TrackParams(
            soundId: soundId,
            type: .granular,
            gain: gain,
            lpHz: lpHz,
            grainLenMsMin: grainLenMs.lowerBound,
            grainLenMsMax: grainLenMs.upperBound,
            density: density,
            pitchMin: pitchRange.lowerBound,
            pitchMax: pitchRange.upperBound,
            panMin: panRange.lowerBound,
            panMax: panRange.upperBound,
            noiseType: .white,
            seed: seed
        )
    }

    /// 创建 DSP 噪声轨道参数
    static func noise(
        _ noiseType: NoiseType,
        gain: Float = 0.5,
        lpHz: Float = 10000,
        seed: UInt64 = 0
    ) -> TrackParams {
        TrackParams(
            soundId: noiseType.rawValue + "_noise",
            type: .dsp,
            gain: gain,
            lpHz: lpHz,
            grainLenMsMin: 0,
            grainLenMsMax: 0,
            density: 0,
            pitchMin: 0,
            pitchMax: 0,
            panMin: 0,
            panMax: 0,
            noiseType: noiseType,
            seed: seed
        )
    }
}
