import AVFoundation
import os

/// 音频引擎管理器
/// 负责 AVAudioEngine 生命周期、轨道管理、信号链搭建
///
/// 槽位设计：预创建 maxSlots 个 AVAudioSourceNode 并永久接入音频图。
/// addTrack/removeTrack 只修改槽位的驱动对象，不改变图结构，避免动态 attach/detach 爆音。
final class AudioEngineManager {

    // MARK: - 常量

    static let maxSlots = 8
    static let sampleRate: Double = 48_000

    // MARK: - 音频图节点

    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

    // MARK: - 预分配槽位

    private var slotDrivers: [TrackSlotDriver] = []     // 索引与 nodes 一一对应
    private var nodes: [AVAudioSourceNode] = []         // 永久接在音频图里
    private var slotMap: [String: Int] = [:]            // soundId -> slot index

    // MARK: - 资产缓存

    private let assetCache = AssetCache(maxCount: 12)

    // MARK: - 状态

    private(set) var isPlaying = false

    /// 系统原因（中断/耳机拔出）导致暂停时的回调（主线程）
    var onPausedBySystem: (() -> Void)?
    /// 淡出完成自动暂停时的回调（主线程）
    var onFadeCompleted: (() -> Void)?

    // MARK: - 全局淡出（main-thread 驱动）

    private var fadeTimer: DispatchSourceTimer?
    private var fadeStartVolume: Float = 0.85
    private var fadeDurationSec: Float = 0
    private var fadeStartTime: CFAbsoluteTime = 0

    // MARK: - Setup

    func setup() throws {
        try configureAudioSession()

        engine.attach(eq)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.85
        configureEQ()

        // 预分配槽位 + 节点，并全部接入音频图
        for _ in 0..<Self.maxSlots {
            let driver = TrackSlotDriver()
            slotDrivers.append(driver)

            let node = AVAudioSourceNode(format: format) { [weak driver] _, _, frameCount, abl -> OSStatus in
                let bufferList = UnsafeMutableAudioBufferListPointer(abl)
                for buf in bufferList {
                    memset(buf.mData, 0, Int(buf.mDataByteSize))
                }
                driver?.render(frameCount: Int(frameCount), abl: bufferList)
                return noErr
            }
            nodes.append(node)
            engine.attach(node)
            engine.connect(node, to: eq, format: format)
        }

        // 安装 RMS 检测 tap，必须在 engine.start() 之前安装
        // 注意：不要 tap mainMixerNode，会导致真机无声输出；改为 tap eq（非输出节点）
        eq.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            var sum: Float = 0
            let data = channelData[0]
            for i in 0..<frameCount { let s = data[i]; sum += s * s }
            let rms = sqrtf(sum / Float(frameCount))
            self.rmsLevel = self.rmsLevel * 0.8 + rms * 0.2   // 指数平滑
        }

        try engine.start()
        isPlaying = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification, object: nil
        )
    }

    // MARK: - 轨道操作

    /// 添加一条轨道（找空闲槽写入，不改变音频图）
    func addTrack(_ params: TrackParams) {
        if slotMap[params.soundId] != nil {
            removeTrack(params.soundId)
        }

        guard let slotIdx = slotDrivers.firstIndex(where: { !$0.isActive }) else {
            print("[AudioEngine] No free slots (max \(Self.maxSlots) tracks)")
            return
        }

        switch params.type {
        case .dsp:
            let dsp = NoiseDSP(type: params.noiseType, params: params)
            slotDrivers[slotIdx].activate(soundId: params.soundId, noiseDSP: dsp, params: params)

        case .granular:
            let trackSeed = Xoshiro256.derive(seed: params.seed, key: params.soundId)
            let scheduler = GrainScheduler(seed: trackSeed, params: params)
            assetCache.loadAsync(params.assetId) { [weak scheduler] buffer in
                if let buffer { scheduler?.loadAsset(buffer: buffer) }
            }
            slotDrivers[slotIdx].activate(soundId: params.soundId, grainScheduler: scheduler, params: params)

        case .binaural:
            let binaural = BinauralBeatDSP(beatHz: params.beatHz, params: params)
            slotDrivers[slotIdx].activate(soundId: params.soundId, binauralDSP: binaural, params: params)
        }

        slotMap[params.soundId] = slotIdx
    }

    /// 移除一条轨道（清空槽位，不改变音频图）
    func removeTrack(_ soundId: String) {
        guard let slotIdx = slotMap.removeValue(forKey: soundId) else { return }
        slotDrivers[slotIdx].deactivate()
    }

    /// 移除所有轨道
    func removeAllTracks() {
        for id in Array(slotMap.keys) { removeTrack(id) }
    }

    /// 更新轨道音量
    func updateTrackGain(_ soundId: String, gain: Float) {
        guard let slotIdx = slotMap[soundId] else { return }
        slotDrivers[slotIdx].updateGain(gain)
    }

    /// 主输出音量（用于 crossfade 动画）
    var masterVolume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    /// 实时 RMS 电平（音频线程写，主线程读，无锁）
    nonisolated(unsafe) private(set) var rmsLevel: Float = 0

    // MARK: - 播放控制

    func play() {
        guard !isPlaying else { return }
        do {
            try configureAudioSession()   // 中断结束后重新激活 session
            try engine.start()
            isPlaying = true
        } catch {
            print("[AudioEngine] play failed: \(error)")
        }
    }

    func pause() {
        guard isPlaying else { return }
        engine.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    // MARK: - 定时淡出

    func startFadeOut(durationSec: Float) {
        fadeTimer?.cancel()
        fadeStartVolume = engine.mainMixerNode.outputVolume
        fadeDurationSec = max(durationSec, 1)
        fadeStartTime = CFAbsoluteTimeGetCurrent()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let elapsed = Float(CFAbsoluteTimeGetCurrent() - self.fadeStartTime)
            let progress = min(elapsed / self.fadeDurationSec, 1.0)
            self.engine.mainMixerNode.outputVolume = self.fadeStartVolume * (1.0 - progress)
            if progress >= 1.0 {
                self.fadeTimer?.cancel()
                self.fadeTimer = nil
                self.pause()
                self.onFadeCompleted?()
            }
        }
        fadeTimer = timer
        timer.resume()
    }

    func cancelFadeOut() {
        fadeTimer?.cancel()
        fadeTimer = nil
        engine.mainMixerNode.outputVolume = 0.85
    }

    // MARK: - 查询

    var activeTrackCount: Int { slotMap.count }
    var activeSoundIds: [String] { Array(slotMap.keys) }

    // MARK: - 配置

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func configureEQ() {
        for band in eq.bands {
            band.filterType = .parametric
            band.frequency = 1000
            band.bandwidth = 1
            band.gain = 0
            band.bypass = true
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            engine.pause()
            isPlaying = false
            DispatchQueue.main.async { [weak self] in self?.onPausedBySystem?() }
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) { play() }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        if reason == .oldDeviceUnavailable {
            engine.pause()
            isPlaying = false
            DispatchQueue.main.async { [weak self] in self?.onPausedBySystem?() }
        }
    }
}

// MARK: - TrackSlotDriver

/// 单槽驱动：持有 NoiseDSP / GrainScheduler / BinauralBeatDSP，用 os_unfair_lock 保护主线程写 / 音频线程读
private final class TrackSlotDriver {

    private let unfairLock: UnsafeMutablePointer<os_unfair_lock>
    private var _soundId: String?
    private var _noiseDSP: NoiseDSP?
    private var _grainScheduler: GrainScheduler?
    private var _binauralDSP: BinauralBeatDSP?
    private var _params: TrackParams?

    init() {
        unfairLock = .allocate(capacity: 1)
        unfairLock.initialize(to: os_unfair_lock())
    }

    deinit {
        unfairLock.deinitialize(count: 1)
        unfairLock.deallocate()
    }

    var isActive: Bool {
        os_unfair_lock_lock(unfairLock)
        defer { os_unfair_lock_unlock(unfairLock) }
        return _soundId != nil
    }

    func activate(soundId: String, noiseDSP: NoiseDSP, params: TrackParams) {
        os_unfair_lock_lock(unfairLock)
        _soundId = soundId
        _noiseDSP = noiseDSP
        _grainScheduler = nil
        _binauralDSP = nil
        _params = params
        os_unfair_lock_unlock(unfairLock)
    }

    func activate(soundId: String, grainScheduler: GrainScheduler, params: TrackParams) {
        os_unfair_lock_lock(unfairLock)
        _soundId = soundId
        _grainScheduler = grainScheduler
        _noiseDSP = nil
        _binauralDSP = nil
        _params = params
        os_unfair_lock_unlock(unfairLock)
    }

    func activate(soundId: String, binauralDSP: BinauralBeatDSP, params: TrackParams) {
        os_unfair_lock_lock(unfairLock)
        _soundId = soundId
        _binauralDSP = binauralDSP
        _noiseDSP = nil
        _grainScheduler = nil
        _params = params
        os_unfair_lock_unlock(unfairLock)
    }

    func deactivate() {
        os_unfair_lock_lock(unfairLock)
        _soundId = nil
        _noiseDSP = nil
        _grainScheduler = nil
        _binauralDSP = nil
        _params = nil
        os_unfair_lock_unlock(unfairLock)
    }

    func updateGain(_ gain: Float) {
        os_unfair_lock_lock(unfairLock)
        _params?.gain = gain
        let dsp = _noiseDSP
        let scheduler = _grainScheduler
        let binaural = _binauralDSP
        let params = _params
        os_unfair_lock_unlock(unfairLock)

        guard let params else { return }
        dsp?.updateParams(params)
        scheduler?.updateParams(params)
        binaural?.updateParams(params)
    }

    // MARK: - 音频线程渲染

    func render(frameCount: Int, abl: UnsafeMutableAudioBufferListPointer) {
        os_unfair_lock_lock(unfairLock)
        let dsp = _noiseDSP
        let scheduler = _grainScheduler
        let binaural = _binauralDSP
        os_unfair_lock_unlock(unfairLock)

        if let dsp {
            dsp.render(frameCount: frameCount, abl: abl)
        } else if let scheduler {
            scheduler.render(frameCount: frameCount, abl: abl)
        } else if let binaural {
            binaural.render(frameCount: frameCount, abl: abl)
        }
        // 空槽：保持 memset 的零输出
    }
}
