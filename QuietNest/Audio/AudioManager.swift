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

    /// 双耳节拍差频映射（左耳 200Hz，右耳 200+beatHz）
    /// Delta 0.5-4Hz：深度睡眠  Theta 4-8Hz：冥想/REM  Alpha 8-13Hz：放松专注  Beta 14-30Hz：清醒专注
    private static let brainBeatHz: [String: Float] = [
        "Delta波": 2.0,
        "Theta波": 6.0,
        "Alpha波": 10.0,
        "Beta波":  20.0,
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

    // MARK: - 每种声音的 grain 参数

    /// 声音资产 ID -> 专属 grain 参数
    /// 未列出的声音使用 TrackParams.granular 默认值
    private static let grainPresets: [String: GrainPreset] = [
        // ── 自然 ────────────────────────────────────────────────────────────
        // 雨声：密集细碎，短粒，轻微 pitch 抖动，宽 pan 包围感
        "rain":         GrainPreset(density: 0.85, lenMs: 30...70,   pitch: -0.2...0.2,  pan: -0.45...0.45),
        // 海浪：舒缓宽广，长粒，pitch 变化适中，宽 pan
        "ocean":        GrainPreset(density: 0.35, lenMs: 250...450, pitch: -0.5...0.5,  pan: -0.4...0.4),
        // 溪流：中等密度，中短粒，轻快感
        "stream":       GrainPreset(density: 0.70, lenMs: 50...110,  pitch: -0.3...0.3,  pan: -0.35...0.35),
        // 微风：稀疏，超长粒，几乎无 pitch，飘逸感
        "wind":         GrainPreset(density: 0.25, lenMs: 350...650, pitch: -0.1...0.1,  pan: -0.3...0.3),
        // 雷声：极稀疏，超长粒，低频感强，无 pitch
        "thunder":      GrainPreset(density: 0.15, lenMs: 400...800, pitch:  0.0...0.0,  pan: -0.2...0.2),
        // 鸟鸣：稀疏短促，高频音节感
        "birds":        GrainPreset(density: 0.30, lenMs: 20...50,   pitch: -0.4...0.6,  pan: -0.4...0.4),
        // 蛙鸣：中等密度，短粒，节奏感
        "frogs":        GrainPreset(density: 0.45, lenMs: 40...80,   pitch: -0.2...0.3,  pan: -0.3...0.3),
        // 蟋蟀：高密度，极短粒，颤音质感
        "crickets":     GrainPreset(density: 0.90, lenMs: 15...30,   pitch: -0.1...0.1,  pan: -0.2...0.2),
        // 篝火：中高密度，短粒，随机爆裂感
        "campfire":     GrainPreset(density: 0.65, lenMs: 25...55,   pitch: -0.15...0.15, pan: -0.25...0.25),
        // 落叶：中等密度，中短粒，沙沙感
        "leaves":       GrainPreset(density: 0.55, lenMs: 35...75,   pitch: -0.2...0.2,  pan: -0.35...0.35),
        // 松林风：稀疏，长粒，低沉宽广
        "forest_wind":  GrainPreset(density: 0.28, lenMs: 300...600, pitch: -0.1...0.15, pan: -0.4...0.4),
        // 瀑布：高密度，中短粒，连续冲击感
        "waterfall":    GrainPreset(density: 0.80, lenMs: 45...90,   pitch: -0.25...0.25, pan: -0.4...0.4),
        // ── 城市 ────────────────────────────────────────────────────────────
        // 咖啡馆：中密度，中粒，环境感
        "cafe":         GrainPreset(density: 0.50, lenMs: 80...160,  pitch: -0.1...0.1,  pan: -0.3...0.3),
        // 图书馆：极稀疏，长粒，静谧感
        "library":      GrainPreset(density: 0.15, lenMs: 200...400, pitch:  0.0...0.0,  pan: -0.1...0.1),
        // 钟摆：稀疏，中粒，节奏感（几乎无 pitch 变化）
        "clock":        GrainPreset(density: 0.20, lenMs: 60...100,  pitch:  0.0...0.0,  pan: -0.05...0.05),
        // 空调：高密度，长粒，平稳连续
        "aircon":       GrainPreset(density: 0.90, lenMs: 200...350, pitch: -0.05...0.05, pan: -0.15...0.15),
        // 风扇：高密度，中粒，平稳
        "fan":          GrainPreset(density: 0.85, lenMs: 100...200, pitch: -0.08...0.08, pan: -0.2...0.2),
        // 火车：中高密度，中粒，节律感
        "train":        GrainPreset(density: 0.60, lenMs: 100...200, pitch: -0.1...0.1,  pan: -0.3...0.3),
        // 机舱：高密度，长粒，低频包围
        "airplane":     GrainPreset(density: 0.88, lenMs: 250...450, pitch: -0.05...0.05, pan: -0.3...0.3),
        // 行驶：中高密度，中长粒，路面起伏感
        "driving":      GrainPreset(density: 0.70, lenMs: 150...300, pitch: -0.1...0.1,  pan: -0.25...0.25),
        // 夜街：低密度，中长粒，零星声响
        "night_street": GrainPreset(density: 0.30, lenMs: 100...250, pitch: -0.2...0.2,  pan: -0.4...0.4),
        // 雨窗：中高密度，短中粒，玻璃感清脆
        "rain_window":  GrainPreset(density: 0.72, lenMs: 30...80,   pitch: -0.15...0.15, pan: -0.3...0.3),
        // ── 预设专属 ────────────────────────────────────────────────────────
        "seagull":      GrainPreset(density: 0.25, lenMs: 30...70,   pitch: -0.3...0.5,  pan: -0.45...0.45),
        "jazz":         GrainPreset(density: 0.40, lenMs: 80...180,  pitch: -0.2...0.2,  pan: -0.35...0.35),
        "cat":          GrainPreset(density: 0.20, lenMs: 60...140,  pitch: -0.3...0.3,  pan: -0.15...0.15),
        "blizzard":     GrainPreset(density: 0.75, lenMs: 200...400, pitch: -0.08...0.08, pan: -0.4...0.4),
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
        } else if let beatHz = Self.brainBeatHz[name] {
            params = .binaural(name: name, beatHz: beatHz, gain: gain)
        } else {
            // 自然/城市类声音 -> 粒子合成，使用声音专属 grain 参数
            let preset = Self.grainPresets[soundId]
            params = .granular(
                soundId: soundId,
                gain: gain,
                density: preset?.density ?? 0.5,
                grainLenMs: preset?.lenMs ?? 80...160,
                pitchRange: preset?.pitch ?? -0.3...0.3,
                panRange: preset?.pan ?? -0.3...0.3,
                seed: seed
            )
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

    /// 随机音景（用 Xoshiro256 保证可复现）
    func randomize(allSoundNames: [String], seed: UInt64) {
        removeAllTracks()
        var rng = Xoshiro256(seed: seed)
        let count = rng.nextInt(in: 2...4)
        // 用 rng 做 Fisher-Yates shuffle 前 count 项
        var pool = allSoundNames
        for i in 0..<min(count, pool.count) {
            let j = i + rng.nextInt(in: 0...(pool.count - 1 - i))
            pool.swapAt(i, j)
            let vol = rng.nextFloat(in: 0.2...0.8)
            addTrack(name: pool[i], gain: vol, seed: seed)
        }
    }

    // MARK: - 预览（2 秒自动停止）

    private static let previewSoundId = "__preview__"
    private var previewTask: DispatchWorkItem?

    /// 预览一段声音，2 秒后自动停止
    /// 若声音已作为普通轨道在播放，则跳过（它已经在发声）
    func previewSound(name: String) {
        let soundId = soundIdForName(name)
        // 已经在播放就不重复加
        if activeTrackIds.contains(soundId) { return }

        stopPreview()

        let previewId = Self.previewSoundId
        let params: TrackParams
        if let noiseType = Self.noiseSounds[name] {
            params = .noise(noiseType, gain: 0.55, seed: 0)
                .withSoundId(previewId)
        } else if let beatHz = Self.brainBeatHz[name] {
            params = .binaural(name: name, beatHz: beatHz, gain: 0.55)
                .withSoundId(previewId)
        } else {
            let preset = Self.grainPresets[soundId]
            params = .granular(
                soundId: previewId,
                assetId: soundId,          // 加载真实资产，但用独立 key
                gain: 0.55,
                density: preset?.density ?? 0.5,
                grainLenMs: preset?.lenMs ?? 80...160,
                pitchRange: preset?.pitch ?? -0.3...0.3,
                panRange: preset?.pan ?? -0.3...0.3,
                seed: 0
            )
        }

        engine.addTrack(params)

        let task = DispatchWorkItem { [weak self] in
            self?.stopPreview()
        }
        previewTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
    }

    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        engine.removeTrack(Self.previewSoundId)
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
        if Self.brainBeatHz[name] != nil {
            return name + "_binaural"
        }
        // 自然/城市类：映射到英文资产 ID；未匹配时回退到中文名
        return Self.assetIdMap[name] ?? name
    }
}

// MARK: - GrainPreset

/// 每种声音的粒子合成参数集合
private struct GrainPreset {
    let density: Float
    let lenMs: ClosedRange<Float>
    let pitch: ClosedRange<Float>
    let pan: ClosedRange<Float>
}
