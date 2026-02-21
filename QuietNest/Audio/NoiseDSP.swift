import Foundation
import AVFoundation

/// DSP 噪声生成器 — 白/粉/棕/蓝噪声实时合成
/// 所有状态为值类型，render 中零分配
final class NoiseDSP {
    private let type: NoiseType
    private var rng: Xoshiro256
    private var gainSmoother: ParamSmoother

    // 粉噪声状态（Paul Kellet 近似）
    private var pinkB0: Float = 0
    private var pinkB1: Float = 0
    private var pinkB2: Float = 0
    private var pinkB3: Float = 0
    private var pinkB4: Float = 0
    private var pinkB5: Float = 0
    private var pinkB6: Float = 0

    // 棕噪声状态
    private var brownLast: Float = 0

    // 蓝噪声状态
    private var blueLast: Float = 0

    // 一阶低通滤波器状态
    private var lpfState: Float = 0

    private let paramBox: AtomicParamBox<TrackParams>

    init(type: NoiseType, params: TrackParams) {
        self.type = type
        self.rng = Xoshiro256(seed: params.seed)
        self.gainSmoother = ParamSmoother(initial: params.gain)
        self.paramBox = AtomicParamBox(params)
    }

    func updateParams(_ params: TrackParams) {
        paramBox.store(params)
    }

    func render(frameCount: Int, abl: UnsafeMutableAudioBufferListPointer) {
        let params = paramBox.load()
        gainSmoother.setTarget(params.gain)

        let outL = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let outR = abl[1].mData!.assumingMemoryBound(to: Float.self)

        // 低通系数
        let lpCoeff = lpfCoefficient(cutoffHz: params.lpHz, sampleRate: 48_000)

        for frame in 0..<frameCount {
            var sample = generateSample()

            // 一阶低通
            lpfState += lpCoeff * (sample - lpfState)
            sample = lpfState

            // 增益平滑
            let gain = gainSmoother.next()
            sample *= gain

            // soft clip 防爆音
            sample = tanh(sample)

            // mono -> stereo（噪声轨道居中）
            outL[frame] += sample
            outR[frame] += sample
        }
    }

    // MARK: - 噪声生成

    private func generateSample() -> Float {
        switch type {
        case .white: return generateWhite()
        case .pink:  return generatePink()
        case .brown: return generateBrown()
        case .blue:  return generateBlue()
        }
    }

    /// 白噪声：均匀分布 [-1, 1]
    private func generateWhite() -> Float {
        rng.nextFloat() * 2.0 - 1.0
    }

    /// 粉噪声：Paul Kellet 近似（1/f 频谱）
    private func generatePink() -> Float {
        let white = generateWhite()
        pinkB0 = 0.99886 * pinkB0 + white * 0.0555179
        pinkB1 = 0.99332 * pinkB1 + white * 0.0750759
        pinkB2 = 0.96900 * pinkB2 + white * 0.1538520
        pinkB3 = 0.86650 * pinkB3 + white * 0.3104856
        pinkB4 = 0.55000 * pinkB4 + white * 0.5329522
        pinkB5 = -0.7616 * pinkB5 - white * 0.0168980
        let pink = pinkB0 + pinkB1 + pinkB2 + pinkB3 + pinkB4 + pinkB5 + pinkB6 + white * 0.5362
        pinkB6 = white * 0.115926
        return pink * 0.11  // 归一化
    }

    /// 棕噪声：白噪声积分 + 泄漏
    private func generateBrown() -> Float {
        let white = generateWhite()
        brownLast = (brownLast + 0.02 * white) * 0.995
        return brownLast * 3.5  // 补偿增益
    }

    /// 蓝噪声：白噪声差分
    private func generateBlue() -> Float {
        let white = generateWhite()
        let blue = white - blueLast
        blueLast = white
        return blue * 0.5  // 归一化
    }

    // MARK: - 滤波器

    /// 一阶低通系数：coeff = 1 - exp(-2π * fc / fs)
    private func lpfCoefficient(cutoffHz: Float, sampleRate: Float) -> Float {
        1.0 - exp(-2.0 * .pi * cutoffHz / sampleRate)
    }
}

// MARK: - BinauralBeatDSP

/// 双耳节拍生成器
/// 左耳：200 Hz 载波正弦波
/// 右耳：(200 + beatHz) Hz 正弦波
/// 两者的差频在大脑中产生感知节拍，需要耳机收听
final class BinauralBeatDSP {

    private let beatHz: Float
    private var gainSmoother: ParamSmoother
    private let paramBox: AtomicParamBox<TrackParams>

    private var phaseL: Float = 0
    private var phaseR: Float = 0

    private static let baseHz: Float = 200.0
    private static let sampleRate: Float = 48_000

    init(beatHz: Float, params: TrackParams) {
        self.beatHz = beatHz
        self.gainSmoother = ParamSmoother(initial: params.gain)
        self.paramBox = AtomicParamBox(params)
    }

    func updateParams(_ params: TrackParams) {
        paramBox.store(params)
    }

    func render(frameCount: Int, abl: UnsafeMutableAudioBufferListPointer) {
        let params = paramBox.load()
        gainSmoother.setTarget(params.gain)

        let outL = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let outR = abl[1].mData!.assumingMemoryBound(to: Float.self)

        let incL = 2 * Float.pi * Self.baseHz / Self.sampleRate
        let incR = 2 * Float.pi * (Self.baseHz + beatHz) / Self.sampleRate
        let twoPi: Float = 2 * .pi

        for i in 0..<frameCount {
            let gain = gainSmoother.next()
            outL[i] += gain * sin(phaseL)
            outR[i] += gain * sin(phaseR)
            phaseL += incL
            if phaseL >= twoPi { phaseL -= twoPi }
            phaseR += incR
            if phaseR >= twoPi { phaseR -= twoPi }
        }
    }
}
