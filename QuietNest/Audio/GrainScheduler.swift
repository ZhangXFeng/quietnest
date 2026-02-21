import AVFoundation
import os

/// 粒子调度器 — 在音频线程 render 回调中执行
/// 从预加载的素材 buffer 中随机选取 grain 并叠加输出
final class GrainScheduler {

    // MARK: - 常量

    static let maxVoices = 32
    static let windowSize = 1024
    static let sampleRate: Float = 48_000

    // MARK: - 素材（主线程写入，音频线程只读，os_unfair_lock 保护）

    private let assetLock: UnsafeMutablePointer<os_unfair_lock>
    private var audioBuffer: AVAudioPCMBuffer?   // 持有 buffer 防止被 LRU 驱逐
    private var pcmData: UnsafePointer<Float>?
    private var pcmFrameCount: Int = 0

    // MARK: - 预分配对象池与状态（值类型，零 ARC）

    private var voices: [GrainVoice] = Array(repeating: GrainVoice(), count: maxVoices)
    private var rng: Xoshiro256
    private var currentSample: Int = 0
    private var nextSpawnSample: Int = 0
    private var gainSmoother: ParamSmoother

    // MARK: - Hann 窗表（预计算）

    private let hannWindow: [Float]

    // MARK: - 参数

    private let paramBox: AtomicParamBox<TrackParams>

    // MARK: - Init

    init(seed: UInt64, params: TrackParams) {
        self.rng = Xoshiro256(seed: seed)
        self.gainSmoother = ParamSmoother(initial: params.gain)
        self.paramBox = AtomicParamBox(params)
        self.assetLock = .allocate(capacity: 1)
        self.assetLock.initialize(to: os_unfair_lock())

        // 预计算 Hann 窗
        var window = [Float](repeating: 0, count: Self.windowSize)
        for i in 0..<Self.windowSize {
            window[i] = 0.5 * (1.0 - cos(2.0 * .pi * Float(i) / Float(Self.windowSize - 1)))
        }
        self.hannWindow = window
    }

    deinit {
        assetLock.deinitialize(count: 1)
        assetLock.deallocate()
    }

    // MARK: - 素材加载（主线程调用）

    func loadAsset(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let ptr = UnsafePointer(channelData[0])
        let count = Int(buffer.frameLength)
        os_unfair_lock_lock(assetLock)
        self.audioBuffer = buffer   // 持有引用，防止 LRU 驱逐后指针悬空
        self.pcmData = ptr
        self.pcmFrameCount = count
        os_unfair_lock_unlock(assetLock)
    }

    // MARK: - 参数更新（主线程调用）

    func updateParams(_ params: TrackParams) {
        paramBox.store(params)
    }

    // MARK: - 渲染（音频线程调用）

    func render(frameCount: Int, abl: UnsafeMutableAudioBufferListPointer) {
        // 在锁下拷贝 asset 指针（拷贝后锁外使用，避免锁住整个 render 循环）
        os_unfair_lock_lock(assetLock)
        let pcm = pcmData
        let pcmLen = pcmFrameCount
        os_unfair_lock_unlock(assetLock)
        guard let pcm, pcmLen > 0 else { return }

        let params = paramBox.load()
        gainSmoother.setTarget(params.gain)

        let outL = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let outR = abl[1].mData!.assumingMemoryBound(to: Float.self)

        hannWindow.withUnsafeBufferPointer { windowBuf in
            let windowPtr = windowBuf.baseAddress!

            for frame in 0..<frameCount {
                // 1) 按调度间隔触发新 grain
                if currentSample >= nextSpawnSample {
                    spawnGrain(params: params, pcmLen: pcmLen)
                    scheduleNext(params: params)
                }

                // 2) 混合所有活跃 grain
                var sampleL: Float = 0
                var sampleR: Float = 0
                for i in 0..<Self.maxVoices where voices[i].isActive {
                    let (l, r) = voices[i].nextSample(
                        pcm: pcm,
                        pcmLen: pcmLen,
                        window: windowPtr,
                        windowSize: Self.windowSize
                    )
                    sampleL += l
                    sampleR += r
                }

                // 3) 增益平滑 + soft clip
                let gain = gainSmoother.next()
                sampleL = tanh(sampleL * gain)
                sampleR = tanh(sampleR * gain)

                outL[frame] += sampleL
                outR[frame] += sampleR
                currentSample += 1
            }
        }
    }

    // MARK: - Grain 调度

    private func spawnGrain(params: TrackParams, pcmLen: Int) {
        // 找一个空闲 voice
        guard let idx = voices.firstIndex(where: { !$0.isActive }) else { return }

        // grain 长度（采样数）
        let minLen = Int(params.grainLenMsMin / 1000.0 * Self.sampleRate)
        let maxLen = Int(params.grainLenMsMax / 1000.0 * Self.sampleRate)
        let grainLen = rng.nextInt(in: max(minLen, 1)...max(maxLen, minLen + 1))

        // 随机起始位置
        let maxStart = max(pcmLen - grainLen, 1)
        let startPos = rng.nextInt(in: 0...maxStart)

        // 随机 pitch、pan、gain
        let pitch = rng.nextFloat(in: params.pitchMin...params.pitchMax)
        let pan = rng.nextFloat(in: params.panMin...params.panMax)
        let voiceGain = rng.nextFloat(in: 0.6...1.0)

        voices[idx].activate(
            startPos: startPos,
            grainLen: grainLen,
            pitch: pitch,
            pan: pan,
            gain: voiceGain
        )
    }

    private func scheduleNext(params: TrackParams) {
        // density -> 调度间隔
        // 高密度 = 短间隔 = 更多重叠
        let density = max(params.density, 0.1)
        let avgGrainLen = (params.grainLenMsMin + params.grainLenMsMax) / 2.0
        let avgGrainSamples = avgGrainLen / 1000.0 * Self.sampleRate
        let overlapFactor: Float = 6.0  // 6x 重叠
        let interval = Int(avgGrainSamples / (density * overlapFactor))
        nextSpawnSample = currentSample + max(interval, 1)
    }
}
