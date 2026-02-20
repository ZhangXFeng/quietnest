import AVFoundation

/// 音频引擎管理器
/// 负责 AVAudioEngine 生命周期、轨道管理、信号链搭建
final class AudioEngineManager {

    // MARK: - 音频图节点

    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

    // MARK: - 轨道管理

    private var trackSlots: [String: TrackSlot] = [:]  // soundId -> slot
    private let assetCache = AssetCache(maxCount: 12)

    private(set) var isPlaying = false

    /// 系统原因（中断/耳机拔出）导致暂停时的回调（主线程回调）
    var onPausedBySystem: (() -> Void)?
    /// 淡出完成自动暂停时的回调（主线程回调）
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

        // tracks -> eq -> mainMixer -> output
        engine.connect(eq, to: engine.mainMixerNode, format: format)

        // mainMixer 音量限制防爆音
        engine.mainMixerNode.outputVolume = 0.85

        configureEQ()

        try engine.start()
        isPlaying = true

        // 监听中断
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        // 监听路由变化（耳机拔出）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    // MARK: - 轨道操作

    /// 添加一条轨道
    func addTrack(_ params: TrackParams) {
        // 如果已存在同名轨道，先移除
        if trackSlots[params.soundId] != nil {
            removeTrack(params.soundId)
        }

        let sourceNode: AVAudioSourceNode
        let slot: TrackSlot

        switch params.type {
        case .dsp:
            let dsp = NoiseDSP(type: params.noiseType, params: params)
            sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, abl -> OSStatus in
                let bufferList = UnsafeMutableAudioBufferListPointer(abl)
                for buf in bufferList {
                    memset(buf.mData, 0, Int(buf.mDataByteSize))
                }
                dsp.render(frameCount: Int(frameCount), abl: bufferList)
                return noErr
            }
            slot = TrackSlot(source: sourceNode, params: params, noiseDSP: dsp, grainScheduler: nil)

        case .granular:
            let trackSeed = Xoshiro256.derive(seed: params.seed, key: params.soundId)
            let scheduler = GrainScheduler(seed: trackSeed, params: params)

            // 异步加载素材
            assetCache.loadAsync(params.soundId) { buffer in
                if let buffer {
                    scheduler.loadAsset(buffer: buffer)
                }
            }

            sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, abl -> OSStatus in
                let bufferList = UnsafeMutableAudioBufferListPointer(abl)
                for buf in bufferList {
                    memset(buf.mData, 0, Int(buf.mDataByteSize))
                }
                scheduler.render(frameCount: Int(frameCount), abl: bufferList)
                return noErr
            }
            slot = TrackSlot(source: sourceNode, params: params, noiseDSP: nil, grainScheduler: scheduler)
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: eq, format: format)
        trackSlots[params.soundId] = slot
    }

    /// 移除一条轨道
    func removeTrack(_ soundId: String) {
        guard let slot = trackSlots.removeValue(forKey: soundId) else { return }
        engine.disconnectNodeOutput(slot.source)
        engine.detach(slot.source)
    }

    /// 移除所有轨道
    func removeAllTracks() {
        let ids = Array(trackSlots.keys)
        for id in ids {
            removeTrack(id)
        }
    }

    /// 更新轨道参数（音量等）
    func updateTrackGain(_ soundId: String, gain: Float) {
        guard var slot = trackSlots[soundId] else { return }
        slot.params.gain = gain
        trackSlots[soundId] = slot
        slot.noiseDSP?.updateParams(slot.params)
        slot.grainScheduler?.updateParams(slot.params)
    }

    // MARK: - 播放控制

    func play() {
        guard !isPlaying else { return }
        do {
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
            let vol = self.fadeStartVolume * (1.0 - progress)
            self.engine.mainMixerNode.outputVolume = max(vol, 0)
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

    var activeTrackCount: Int { trackSlots.count }
    var activeSoundIds: [String] { Array(trackSlots.keys) }

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
                if options.contains(.shouldResume) {
                    play()
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        // 耳机拔出时暂停（Apple 官方推荐行为）
        if reason == .oldDeviceUnavailable {
            engine.pause()
            isPlaying = false
            DispatchQueue.main.async { [weak self] in self?.onPausedBySystem?() }
        }
    }
}

// MARK: - TrackSlot

private struct TrackSlot {
    let source: AVAudioSourceNode
    var params: TrackParams
    let noiseDSP: NoiseDSP?
    let grainScheduler: GrainScheduler?
}
