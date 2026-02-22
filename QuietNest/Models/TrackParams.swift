import Foundation

/// 轨道类型
enum TrackType: String, Codable {
    case granular   // 粒子合成（真实录音素材）
    case dsp        // DSP 实时生成（噪声类）
    case binaural   // 双耳节拍（纯正弦波，左右耳不同频率）
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
    let soundId: String         // 引擎唯一 key（也用于 AssetCache 查找，除非 assetId 另行指定）
    let assetId: String         // 资产文件名（默认等于 soundId；预览时可单独指定）
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

    // 双耳节拍参数（type == .binaural 时使用）
    var beatHz: Float           // 双耳差频（Hz）：Delta≈2, Theta≈6, Alpha≈10, Beta≈20

    var seed: UInt64

    /// 返回 soundId 替换后的副本（用于预览）
    func withSoundId(_ newId: String) -> TrackParams {
        TrackParams(
            soundId: newId, assetId: assetId, type: type,
            gain: gain, lpHz: lpHz,
            grainLenMsMin: grainLenMsMin, grainLenMsMax: grainLenMsMax,
            density: density,
            pitchMin: pitchMin, pitchMax: pitchMax,
            panMin: panMin, panMax: panMax,
            noiseType: noiseType, beatHz: beatHz, seed: seed
        )
    }

    /// 创建粒子合成轨道参数
    /// - Parameters:
    ///   - soundId: 引擎唯一 key；assetId 默认与 soundId 相同
    ///   - assetId: 资产文件名（不含后缀），nil 时使用 soundId
    static func granular(
        soundId: String,
        assetId: String? = nil,
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
            assetId: assetId ?? soundId,
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
            beatHz: 0,
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
            assetId: noiseType.rawValue + "_noise",
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
            beatHz: 0,
            seed: seed
        )
    }

    /// 创建双耳节拍轨道参数
    /// - Parameters:
    ///   - name: 声音名称（如 "Delta波"）
    ///   - beatHz: 双耳差频，典型值：Delta≈2, Theta≈6, Alpha≈10, Beta≈20
    static func binaural(
        name: String,
        beatHz: Float,
        gain: Float = 0.5
    ) -> TrackParams {
        TrackParams(
            soundId: name + "_binaural",
            assetId: name + "_binaural",
            type: .binaural,
            gain: gain,
            lpHz: 10000,
            grainLenMsMin: 0,
            grainLenMsMax: 0,
            density: 0,
            pitchMin: 0,
            pitchMax: 0,
            panMin: 0,
            panMax: 0,
            noiseType: .white,
            beatHz: beatHz,
            seed: 0
        )
    }
}
