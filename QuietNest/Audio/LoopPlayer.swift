import AVFoundation
import os

/// 顺序循环播放器 — 直接读取 PCM buffer 并无缝循环
/// 声音与原始素材完全一致，无粒子合成变形
final class LoopPlayer {

    // MARK: - 素材（主线程写，音频线程读，assetLock 保护）

    private let assetLock: UnsafeMutablePointer<os_unfair_lock>
    private var audioBuffer: AVAudioPCMBuffer?   // 持有引用防止释放
    private var pcmData: UnsafePointer<Float>?
    private var pcmFrameCount: Int = 0

    // MARK: - 播放状态

    private var readPos: Double = 0             // 当前读取位置（支持分数位，用于未来变速）
    private var gainSmoother: ParamSmoother
    private let paramBox: AtomicParamBox<TrackParams>

    // MARK: - 诊断

    nonisolated(unsafe) private var _hasLoggedFirstAudio = false

    // MARK: - Init

    init(params: TrackParams) {
        self.gainSmoother = ParamSmoother(initial: params.gain)
        self.paramBox = AtomicParamBox(params)
        self.assetLock = .allocate(capacity: 1)
        self.assetLock.initialize(to: os_unfair_lock())
    }

    deinit {
        assetLock.deinitialize(count: 1)
        assetLock.deallocate()
    }

    // MARK: - 素材加载（主线程调用）

    func loadAsset(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            print("[LoopPlayer] ❌ loadAsset: floatChannelData nil (format=\(buffer.format))")
            return
        }
        let ptr = UnsafePointer(channelData[0])
        let count = Int(buffer.frameLength)
        print("[LoopPlayer] ✓ loadAsset: \(count) frames")
        os_unfair_lock_lock(assetLock)
        audioBuffer = buffer
        pcmData = ptr
        pcmFrameCount = count
        os_unfair_lock_unlock(assetLock)
    }

    // MARK: - 参数更新（主线程调用）

    func updateParams(_ params: TrackParams) {
        paramBox.store(params)
    }

    // MARK: - 渲染（音频线程调用）

    func render(frameCount: Int, abl: UnsafeMutableAudioBufferListPointer) {
        os_unfair_lock_lock(assetLock)
        let pcm = pcmData
        let pcmLen = pcmFrameCount
        os_unfair_lock_unlock(assetLock)
        guard let pcm, pcmLen > 0 else { return }

        let params = paramBox.load()
        gainSmoother.setTarget(params.gain)

        let outL = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let outR = abl[1].mData!.assumingMemoryBound(to: Float.self)

        for frame in 0..<frameCount {
            // 整数位置取样（无插值，保持原始音质）
            let idx = Int(readPos) % pcmLen
            let sample = pcm[idx] * gainSmoother.next()

            // 单声道居中输出（等功率）
            let s = sample * 0.707
            outL[frame] += s
            outR[frame] += s

            readPos += 1.0
            if readPos >= Double(pcmLen) { readPos -= Double(pcmLen) }

            if !_hasLoggedFirstAudio && sample != 0 {
                _hasLoggedFirstAudio = true
                print("[LoopPlayer] ✓ First audio sample generated")
            }
        }
    }
}
