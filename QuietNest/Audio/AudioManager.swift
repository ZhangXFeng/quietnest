import SwiftUI
import Combine

/// SwiftUI 桥接层 — 连接 UI 与音频引擎
/// ObservableObject，供 View 绑定
@MainActor
final class AudioManager: ObservableObject {

    @Published private(set) var isPlaying = false
    @Published private(set) var isEngineReady = false

    private let engine = AudioEngineManager()

    /// 已添加到引擎的轨道 soundId 集合
    private var activeTrackIds: Set<String> = []

    // MARK: - 声音 ID 映射（UI 名称 -> 引擎 soundId）

    /// 噪声类声音名称
    private static let noiseSounds: [String: NoiseType] = [
        "白噪音": .white,
        "粉噪音": .pink,
        "棕噪音": .brown,
        "灰噪音": .brown,   // 灰噪音近似用棕噪音
        "蓝噪音": .blue
    ]

    /// 频率类声音（DSP 正弦波，MVP 先用噪声近似）
    private static let brainSounds: Set<String> = [
        "Delta波", "Theta波", "Alpha波", "Beta波"
    ]

    /// 中文声音名称 -> 英文资产文件名（不含后缀）
    /// AssetCache 会按此 ID 在 bundle 中查找 .caf/.wav 文件
    private static let assetIdMap: [String: String] = [
        // 自然
        "雨声":   "rain",
        "海浪":   "ocean",
        "溪流":   "stream",
        "微风":   "wind",
        "雷声":   "thunder",
        "鸟鸣":   "birds",
        "蛙鸣":   "frogs",
        "蟋蟀":   "crickets",
        "篝火":   "campfire",
        "落叶":   "leaves",
        "松林风": "forest_wind",
        "瀑布":   "waterfall",
        // 城市
        "咖啡馆": "cafe",
        "图书馆": "library",
        "钟摆":   "clock",
        "空调":   "aircon",
        "风扇":   "fan",
        "火车":   "train",
        "机舱":   "airplane",
        "行驶":   "driving",
        "夜街":   "night_street",
        "雨窗":   "rain_window",
        // 海鸥（出现在预设中）
        "海鸥":   "seagull",
        // 爵士（出现在预设中）
        "爵士":   "jazz",
        // 猫咪（出现在预设中）
        "猫咪":   "cat",
        // 风雪
        "风雪":   "blizzard",
    ]

    // MARK: - 生命周期

    func setup() {
        engine.onPausedBySystem = { [weak self] in
            self?.isPlaying = false
        }
        engine.onFadeCompleted = { [weak self] in
            self?.isPlaying = false
        }
        do {
            try engine.setup()
            isPlaying = true
            isEngineReady = true
        } catch {
            print("[AudioManager] setup failed: \(error)")
        }
    }

    // MARK: - 播放控制

    func play() {
        engine.play()
        isPlaying = true
    }

    func pause() {
        engine.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    // MARK: - 轨道管理

    /// 添加一条轨道（从 UI 的 sound name 映射到引擎参数）
    func addTrack(name: String, gain: Float = 0.5, seed: UInt64 = 0) {
        let soundId = soundIdForName(name)
        guard !activeTrackIds.contains(soundId) else { return }

        let params: TrackParams
        if let noiseType = Self.noiseSounds[name] {
            params = .noise(noiseType, gain: gain, seed: seed)
        } else if Self.brainSounds.contains(name) {
            // 脑波频率 MVP 先用粉噪音低通近似
            params = .noise(.pink, gain: gain, lpHz: 500, seed: seed)
        } else {
            // 自然/城市类声音 -> 粒子合成
            params = .granular(soundId: soundId, gain: gain, seed: seed)
        }

        engine.addTrack(params)
        activeTrackIds.insert(soundId)
    }

    /// 移除一条轨道
    func removeTrack(name: String) {
        let soundId = soundIdForName(name)
        engine.removeTrack(soundId)
        activeTrackIds.remove(soundId)
    }

    /// 更新轨道音量
    func updateVolume(name: String, volume: Double) {
        let soundId = soundIdForName(name)
        engine.updateTrackGain(soundId, gain: Float(volume))
    }

    /// 移除所有轨道
    func removeAllTracks() {
        engine.removeAllTracks()
        activeTrackIds.removeAll()
    }

    /// 应用预设（替换所有轨道）
    func applyPreset(tracks: [(name: String, volume: Double)], seed: UInt64 = 0) {
        removeAllTracks()
        for track in tracks {
            addTrack(name: track.name, gain: Float(track.volume), seed: seed)
        }
    }

    /// 随机音景
    func randomize(allSoundNames: [String], seed: UInt64) {
        removeAllTracks()
        var rng = Xoshiro256(seed: seed)
        let count = rng.nextInt(in: 2...4)
        let shuffled = allSoundNames.shuffled()
        for i in 0..<min(count, shuffled.count) {
            let vol = Float(rng.nextFloat(in: 0.2...0.8))
            addTrack(name: shuffled[i], gain: vol, seed: seed)
        }
    }

    // MARK: - 定时

    func startFadeOut(durationSec: Float = 300) {
        engine.startFadeOut(durationSec: durationSec)
    }

    func cancelFadeOut() {
        engine.cancelFadeOut()
    }

    // MARK: - 工具

    func isTrackActive(name: String) -> Bool {
        activeTrackIds.contains(soundIdForName(name))
    }

    private func soundIdForName(_ name: String) -> String {
        if let noiseType = Self.noiseSounds[name] {
            return noiseType.rawValue + "_noise"
        }
        // 自然/城市类：映射到英文资产 ID；未匹配时回退到中文名
        return Self.assetIdMap[name] ?? name
    }
}
