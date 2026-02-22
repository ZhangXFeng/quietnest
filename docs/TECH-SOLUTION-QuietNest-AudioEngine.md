# QuietNest 技术方案（粒子合成音频核心）v2.1

## 1. 目标与范围
本文档定义 QuietNest iOS App 的音频引擎实现方案，覆盖：
- 基于真实录音素材的粒子合成（Granular Synthesis）引擎架构
- 素材管理与资源策略
- 噪声类轨道的混合方案（粒子合成 + 轻量 DSP）
- 场景参数模型与随机可复现机制
- 性能、稳定性、测试与迭代计划

不包含：
- 账号体系、云同步、运营后台
- 复杂音乐生成（MIDI/和声/旋律编排）

### 1.1 实现语言：纯 Swift
全栈采用 Swift 实现，不引入 C/C++/ObjC。理由：
- 粒子合成的核心操作（buffer 读取、窗口查表、浮点累加）在 Swift `-O` 优化下与 C++ 性能一致。
- 通过值类型（struct）+ `UnsafePointer` 可完全规避 ARC 在音频线程的干扰。
- 单一语言降低构建与调试复杂度，一个人迭代更快。
- Apple Accelerate/vDSP 框架可从 Swift 原生调用，满足未来高级 DSP 需求（FFT、频谱分析等）。
- 如未来有跨平台需求，可将热点函数替换为 C 实现，`AVAudioSourceNode` render 回调的接口不变。

### 1.2 与 v1.0 方案的核心差异
v1.0 采用纯 DSP 程序化合成所有声音（噪声滤波 + 数学建模事件）。
v2.x 改为**粒子合成为主、DSP 为辅**的混合方案：
- 自然/城市/频率类声音：粒子合成（真实录音素材切片重组）
- 噪声类声音（白/粉/棕/蓝）：保留 DSP 实时生成（数学生成的噪声本身就是"正确"的）

理由：纯 DSP 合成的雨声、鸟鸣、咖啡馆等自然/环境音，听感上限远低于真实录音。粒子合成同时获得"真实听感"与"永不循环"两个关键优势。

## 2. 核心设计原则
- **真实优先**：自然/环境声基于高质量实地录音，不用数学模型仿真。
- **永不循环**：粒子随机重组 + 参数微扰，消除可感知的重复模式。
- **实时安全**：音频线程仅做采样读取与混合，不分配内存、不做 IO。
- **参数驱动**：预设保存参数快照（grain 策略 + 增益 + 滤波），不保存混音文件。
- **可复现随机**：同一 `seed + preset` 生成一致的 grain 调度序列。
- **低功耗**：后台运行可持续，粒子合成 CPU 开销低于纯 DSP 方案。

## 3. 总体架构
### 3.1 分层
1. **UI 层**
   - 展示轨道、参数、定时器、预设。
   - 不直接做音频处理，仅发送控制命令。

2. **Audio Control 层**
   - 统一接收 UI 命令，更新引擎参数。
   - 管理场景切换、淡入淡出、播放状态机。
   - 负责素材加载调度（预加载到内存）。

3. **Granular Engine 层（核心）**
   - 粒子调度器：从预加载的素材 buffer 中选取 grain 并叠加。
   - DSP 子模块：白/粉/棕/蓝噪声实时生成。
   - 混音、滤波、动态处理（limiter）。

4. **Asset 层（新增）**
   - 管理音频素材文件（加载、解码、缓存）。
   - 每种声音对应一个 30~60 秒的高质量录音文件。
   - 支持按需加载与 LRU 缓存。

5. **Persistence 层**
   - 保存参数化预设、用户偏好、seed。
   - 本地 JSON + UserDefaults（MVP）。

### 3.2 iOS 组件
- `AVAudioEngine` — 音频图管理
- `AVAudioSourceNode` — 实时采样输出（粒子混合在此完成）
- `AVAudioMixerNode` — 分轨混音
- `AVAudioUnitEQ` — 场景色彩滤波
- `AVAudioUnitReverb` — 轻量空间感
- `AVAudioUnitDynamicsProcessor` — 防爆音
- `AVAudioFile` / `AVAudioPCMBuffer` — 素材加载与解码
- `Accelerate` / `vDSP` — 未来高级 DSP（FFT、频谱分析、批量向量运算）

## 4. 音频信号链

```
TrackSourceNode_0 (granular/dsp) ─┐
TrackSourceNode_1 (granular/dsp) ─┼─> TrackMixer ─> SceneEQ ─> Reverb(send)
TrackSourceNode_2 (granular/dsp) ─┤       ↓
        ...                       ┘   MasterDynamics(limiter) ─> MainMixer ─> Output
```

说明：
- 每条轨道拥有独立的 `AVAudioSourceNode`，在各自的 render 回调中完成粒子合成或 DSP 生成。
- `TrackMixer` 保留每轨独立增益（0~1）与静音态。
- `MasterDynamics` 必须在输出前，防止多轨叠加后峰值失真。

与 v1.0 的区别：v1.0 所有轨道共享一个 SourceNode 统一渲染；v2.0 每轨独立 SourceNode，便于按需加载/卸载素材、独立控制粒子参数。

## 5. 粒子合成核心

### 5.1 基本概念
粒子合成将一段连续录音视为"素材池"，从中随机截取微小片段（grain），每个 grain 独立施加包络、pitch 偏移、pan 偏移后叠加输出。大量 grain 重叠形成连续声流，听感接近原始录音但永不重复。

```
素材 buffer (30~60s 录音)
  │
  ├─ grain_0: [startPos=12400, len=4800, pitch=+0.02, pan=-0.15, gain=0.8]
  ├─ grain_1: [startPos=38200, len=6400, pitch=-0.01, pan=+0.22, gain=0.7]
  ├─ grain_2: [startPos=5100,  len=5200, pitch=+0.00, pan=-0.05, gain=0.9]
  └─ ...
      ↓ 叠加 + 包络窗口
   连续输出流（永不循环）
```

### 5.2 Grain 参数
每个 grain 由以下参数定义：

| 参数 | 说明 | 建议范围 |
|---|---|---|
| `startPos` | 在素材 buffer 中的起始采样点 | 随机，0 ~ bufferLength-grainLen |
| `grainLen` | grain 长度（采样数） | 2400~9600（50~200ms @48kHz） |
| `pitch` | 音高偏移（半音） | -0.5 ~ +0.5 semitones |
| `pan` | 立体声位置 | -0.4 ~ +0.4 |
| `gain` | 增益 | 0.5 ~ 1.0 |
| `envelope` | 包络窗口类型 | Hann 窗（默认） |

### 5.3 粒子调度策略
每条粒子合成轨道维护一个调度器（GrainScheduler）：
- **密度（density）**：控制单位时间内活跃 grain 数量。`density=0.5` 约 8~12 个重叠 grain，`density=1.0` 约 16~24 个。
- **调度间隔**：`interval = grainLen / (density * overlapFactor)`
- **重叠因子（overlapFactor）**：建议 4~8，确保相邻 grain 充分重叠，输出无间隙。

每到调度时刻：
1. 用 PRNG 从素材 buffer 中随机选取 `startPos`。
2. 随机化 `grainLen`、`pitch`、`pan`、`gain`（在约束范围内）。
3. 从 grain 对象池取一个空闲 voice，赋参数并激活。
4. voice 播放完毕后自动归还池。

### 5.4 Grain 包络窗口
每个 grain 必须施加平滑包络，否则边界会产生 click：
- **Hann 窗**（推荐）：`w(n) = 0.5 * (1 - cos(2π * n / N))`
- 计算简单，首尾归零，重叠后幅度平稳。
- 窗口表可预计算存储，渲染时查表乘法。

### 5.5 噪声类轨道（DSP 保留）
白/粉/棕/蓝噪声不需要录音素材，保留 DSP 实时生成：

1. **白噪声** — `white[n] = random(-1, 1)`
2. **粉噪声** — Paul Kellet 近似滤波
3. **棕噪声** — `brown[n] = (brown[n-1] + k * white[n]) * leak`，`leak=0.98~0.995`
4. **蓝噪声** — `blue[n] = white[n] - white[n-1]`，幅度归一

噪声轨道使用独立的 SourceNode，render 回调中直接生成，不走粒子调度。

### 5.6 参数平滑与无点击控制
所有可变参数（音量、滤波 cutoff、density）不可瞬变：
- 一阶平滑：`y[n] = y[n-1] + a * (target - y[n-1])`
- 建议平滑时间常数 `20~80ms`。

开始/停止与场景切换：
- 统一执行 `50~300ms` ramp/crossfade，避免 click/pop。

### 5.7 立体声空间处理
- 每个 grain 随机 `pan`（-0.4 ~ +0.4），随时间轻微漂移。
- 不同轨道可设置基础 `pan` 偏移（如溪流偏左、鸟鸣偏右）。
- 避免过宽导致耳机疲劳。

## 6. 素材管理

### 6.1 素材规格
- 格式：CAF 或 WAV，48kHz，16bit，单声道（粒子合成时由 pan 生成立体声）。
- 时长：每种声音 30~60 秒。
- 质量要求：无明显背景噪音、无突发异响、录音电平稳定。

### 6.2 素材来源优先级
1. **自行录制** — 版权最干净，成本最低，可控性最强。
2. **CC0 公共领域素材**（Freesound.org、Pixabay Audio）— 免费可商用，无需署名。
3. **CC BY 素材**（Freesound.org）— 免费可商用，需在 App 内署名致谢。
4. **付费素材库**（Artlist、Epidemic Sound）— 质量稳定，买断授权。

**禁止使用 CC BY-NC 素材**（不可商用）。

### 6.3 素材清单（MVP 30 种声音）
| 分类 | 声音 | 素材需求 |
|---|---|---|
| 自然 | 雨声、海浪、溪流、微风、雷声、鸟鸣、蛙鸣、蟋蟀、篝火、落叶、松林风、瀑布 | 各 30~60s |
| 城市 | 咖啡馆、图书馆、钟摆、空调、风扇、火车、机舱、行驶、夜街、雨窗 | 各 30~60s |
| 噪声 | 白噪音、粉噪音、棕噪音、灰噪音、蓝噪音 | DSP 生成，无需素材 |
| 频率 | Delta 波、Theta 波、Alpha 波、Beta 波 | DSP 生成，无需素材 |

需要录音素材的声音：22 种 × 约 1~3MB = **约 22~66MB**。
可在首次安装时内置核心素材（雨声、篝火等 10 种），其余按需下载。

### 6.4 素材加载策略
- **预加载**：当前活跃轨道的素材常驻内存（解码为 PCM buffer）。
- **懒加载**：非活跃声音在用户添加轨道时异步加载。
- **LRU 缓存**：最多同时缓存 12 个素材 buffer，超出时淘汰最久未用的。
- 加载发生在控制线程，完成后通过原子指针交给音频线程，音频线程本身不做 IO。

## 7. 场景参数化模型
每个预设保存为参数快照：

```json
{
  "presetId": "sleep_rain_room",
  "name": "雨夜书房",
  "seed": 104729,
  "tracks": [
    {
      "soundId": "rain",
      "type": "granular",
      "gain": 0.70,
      "grainLenMs": [80, 160],
      "density": 0.6,
      "pitchRange": [-0.3, 0.3],
      "panRange": [-0.3, 0.3],
      "lpHz": 8000
    },
    {
      "soundId": "fireplace",
      "type": "granular",
      "gain": 0.40,
      "grainLenMs": [60, 120],
      "density": 0.5,
      "pitchRange": [-0.2, 0.2],
      "panRange": [-0.2, 0.2],
      "lpHz": 6000
    },
    {
      "soundId": "clock",
      "type": "granular",
      "gain": 0.26,
      "grainLenMs": [100, 200],
      "density": 0.3,
      "pitchRange": [-0.1, 0.1],
      "panRange": [-0.1, 0.1],
      "lpHz": 10000
    }
  ],
  "space": { "reverbMix": 0.12 },
  "master": { "gain": 0.85 }
}
```

噪声类轨道的参数模型：
```json
{
  "soundId": "pink_noise",
  "type": "dsp",
  "noiseType": "pink",
  "gain": 0.42,
  "lpHz": 4200
}
```

参数建议范围：
- `gain`: `0.0~1.0`
- `density`: `0.1~1.0`（映射到 grain 重叠数）
- `grainLenMs`: `[50, 200]`（最小/最大 grain 长度）
- `pitchRange`: `[-1.0, 1.0]` 半音
- `panRange`: `[-0.5, 0.5]`
- `lpHz`: `500~16000`
- `reverbMix`: `0.0~0.25`

## 8. 随机与可复现机制
- 使用固定种子 PRNG（推荐 Xoshiro256**，速度快、质量好）。
- 每个预设保存 `globalSeed`，按轨道派生子种子：
  - `trackSeed = hash(globalSeed, trackIndex)`
- 每条轨道的 GrainScheduler 用 `trackSeed` 初始化 PRNG，决定：
  - grain 的 `startPos`、`pitch`、`pan`、`gain` 随机序列。
- 同一 `seed + preset` 产生完全一致的 grain 调度序列。
- "随机音景"功能：生成新 seed + 从全量声音中随机选轨道与参数。

## 9. iOS 实现骨架（Swift）

### 9.1 Swift 实时安全规范
在 `AVAudioSourceNode` 的 render 回调中，必须遵守以下规则：

```swift
// ✅ 安全：值类型（struct），无 ARC
struct GrainVoice { var cursor: Int = 0; var gain: Float = 0 }
var voices: [GrainVoice] = Array(repeating: GrainVoice(), count: 32)

// ✅ 安全：UnsafePointer 直接访问素材 buffer，无 ARC
let floatPtr = buffer.floatChannelData![0]
let sample = floatPtr[readPos]

// ✅ 安全：预计算查表
let envelope = hannWindow[windowIdx]

// ❌ 禁止：引用类型（class）的属性访问 → 触发 retain/release
let scheduler = someClassInstance  // ARC 计数变化

// ❌ 禁止：String 拼接、Array append → 触发 malloc
let msg = "frame: \(frame)"       // 堆分配
voices.append(newVoice)            // 可能扩容

// ❌ 禁止：闭包捕获 → 可能触发堆分配
let closure = { self.process() }   // 捕获 self
```

核心原则：render 回调中**只用值类型 + UnsafePointer + 预分配数组 + 纯算术**。

### 9.2 AudioEngineManager

```swift
/// 管理音频引擎与轨道
final class AudioEngineManager {
    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private let limiter = AVAudioUnitDynamicsProcessor()
    private var trackNodes: [String: TrackNode] = [:]  // soundId -> node
    private let assetCache = AssetCache(maxCount: 12)

    func setup() throws {
        engine.attach(eq)
        engine.attach(limiter)

        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        engine.connect(eq, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)

        configureLimiter()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try engine.start()
    }

    /// 添加一条轨道
    func addTrack(_ params: TrackParams) {
        let sourceNode: AVAudioSourceNode

        if params.type == .granular {
            let buffer = assetCache.load(params.soundId)
            let scheduler = GrainScheduler(buffer: buffer, seed: params.seed)
            sourceNode = AVAudioSourceNode { _, _, frameCount, abl -> OSStatus in
                scheduler.render(frameCount: Int(frameCount), abl: abl, params: params)
                return noErr
            }
        } else {
            let dsp = NoiseDSP(type: params.noiseType)
            sourceNode = AVAudioSourceNode { _, _, frameCount, abl -> OSStatus in
                dsp.render(frameCount: Int(frameCount), abl: abl, params: params)
                return noErr
            }
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: eq, format: format)
        trackNodes[params.soundId] = TrackNode(source: sourceNode, params: params)
    }

    /// 移除一条轨道
    func removeTrack(_ soundId: String) {
        guard let node = trackNodes.removeValue(forKey: soundId) else { return }
        engine.disconnectNodeOutput(node.source)
        engine.detach(node.source)
    }

    /// 更新轨道参数（音量等），通过原子快照下发
    func updateTrack(_ soundId: String, params: TrackParams) {
        trackNodes[soundId]?.updateParams(params)
    }
}
```

### 9.3 GrainScheduler

```swift
/// 粒子调度器 — 在音频线程 render 回调中执行
/// 注意：此类的所有可变状态仅由音频线程访问，无需加锁。
/// 参数更新通过 os_unfair_lock-free 的原子快照从主线程下发。
final class GrainScheduler {
    // ---- 素材（控制线程加载后通过原子指针交给音频线程）----
    private let pcmData: UnsafePointer<Float>   // 素材裸指针，避免 ARC
    private let pcmFrameCount: Int

    // ---- 预分配对象池（值类型数组，render 中零分配）----
    private var voices: [GrainVoice] = Array(repeating: GrainVoice(), count: 32)
    private var rng: Xoshiro256StarStar         // 确定性 PRNG（struct，值类型）
    private var currentSample: Int = 0
    private var nextSpawnSample: Int = 0
    private let hannWindow: [Float]             // 预计算 1024 点 Hann 窗

    init(buffer: AVAudioPCMBuffer, seed: UInt64) {
        self.pcmData = UnsafePointer(buffer.floatChannelData![0])
        self.pcmFrameCount = Int(buffer.frameLength)
        self.rng = Xoshiro256StarStar(seed: seed)
        self.hannWindow = Self.makeHannWindow(size: 1024)
    }

    func render(frameCount: Int, abl: UnsafeMutableAudioBufferListPointer, params: TrackParams) {
        let outL = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let outR = abl[1].mData!.assumingMemoryBound(to: Float.self)

        for frame in 0..<frameCount {
            // 1) 按调度间隔触发新 grain
            if currentSample >= nextSpawnSample {
                spawnGrain(params: params)
                scheduleNext(params: params)
            }

            // 2) 混合所有活跃 grain（纯值类型操作）
            var sampleL: Float = 0
            var sampleR: Float = 0
            for i in 0..<voices.count where voices[i].isActive {
                let (l, r) = voices[i].nextSample(pcm: pcmData, pcmLen: pcmFrameCount, window: hannWindow)
                sampleL += l
                sampleR += r
            }

            // 3) 增益平滑
            sampleL *= smoothedGain
            sampleR *= smoothedGain

            outL[frame] += sampleL
            outR[frame] += sampleR
            currentSample += 1
        }
    }

    private static func makeHannWindow(size: Int) -> [Float] {
        (0..<size).map { i in
            0.5 * (1.0 - cos(2.0 * .pi * Float(i) / Float(size - 1)))
        }
    }
}
```

### 9.4 GrainVoice

```swift
/// 单个 grain 播放实例（struct 值类型，无 ARC 开销）
struct GrainVoice {
    var isActive: Bool = false
    var startPos: Int = 0           // 素材中的起始采样点
    var grainLen: Int = 0           // grain 总长度（采样数）
    var cursor: Int = 0             // 当前播放位置
    var pitch: Float = 0            // 半音偏移
    var pan: Float = 0              // -1~1
    var gain: Float = 1.0

    /// 从素材裸指针读取采样，施加窗口与 pan，返回立体声
    mutating func nextSample(pcm: UnsafePointer<Float>, pcmLen: Int, window: [Float]) -> (Float, Float) {
        guard isActive else { return (0, 0) }

        // Hann 窗查表
        let windowIdx = cursor * (window.count - 1) / grainLen
        let envelope = window[windowIdx]

        // 素材读取（pitch 偏移 = 变速读取）
        let readStep = 1.0 + pitch * 0.0595     // 1 semitone ≈ 5.95%
        let readPos = startPos + Int(Float(cursor) * readStep)
        let safePos = readPos % pcmLen
        let sample = pcm[safePos] * envelope * gain

        // equal-power pan
        let panR = (pan + 1.0) * 0.5
        let left  = sample * sqrt(1.0 - panR)
        let right = sample * sqrt(panR)

        cursor += 1
        if cursor >= grainLen { isActive = false }

        return (left, right)
    }
}
```

### 9.5 参数下发（无锁原子快照）

```swift
/// 用于从主线程向音频线程传递参数的无锁容器
/// 利用 Swift Atomics 或 os_unfair_lock 实现
final class AtomicParamBox<T> {
    private var storage: UnsafeMutablePointer<T>
    private let lock = os_unfair_lock_t.allocate(capacity: 1)

    init(_ initial: T) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: initial)
        lock.initialize(to: os_unfair_lock())
    }

    /// 主线程写入
    func store(_ value: T) {
        os_unfair_lock_lock(lock)
        storage.pointee = value
        os_unfair_lock_unlock(lock)
    }

    /// 音频线程读取（os_unfair_lock 不会导致优先级反转）
    func load() -> T {
        os_unfair_lock_lock(lock)
        let v = storage.pointee
        os_unfair_lock_unlock(lock)
        return v
    }
}
```

### 9.6 实时安全总结
| 关注点 | 策略 |
|---|---|
| ARC 干扰 | GrainVoice 用 struct；素材用 UnsafePointer；render 中不捕获引用类型 |
| 内存分配 | 对象池预分配，hannWindow 预计算，数组固定大小不 append |
| 参数传递 | os_unfair_lock 原子快照（不会优先级反转） |
| 素材加载 | 控制线程解码为 PCM，完成后原子交换指针给音频线程 |
| 随机数 | Xoshiro256** 用 struct 实现，纯算术，无系统调用 |

## 10. 线程模型与实时安全
- **主线程**：UI 交互与参数编辑。
- **控制线程**：素材加载/解码、参数合并、状态机处理（可用 `DispatchQueue` 串行队列）。
- **音频线程（实时）**：仅拉取最新参数快照 + 从预加载 buffer 读采样 + grain 混合。

禁止在音频回调中做：
- `malloc/free`（包括 Swift Array/String/Dictionary 的隐式扩容）
- ARC 引用计数操作（不访问 class 实例属性）
- 文件 IO、网络 IO
- 锁等待（`NSLock`/`pthread_mutex`/`DispatchSemaphore` — `os_unfair_lock` 除外）
- Objective-C 动态消息（避免在 render 中调用 `@objc` 方法）
- Swift `print()`、`String` 插值、`assert` message

## 11. 后台播放与系统会话
- `AVAudioSession` 建议：
  - category: `.playback`
  - mode: `.default`
  - options: 依据需求决定是否 `mixWithOthers`
- 配置后台音频能力（Background Modes -> Audio）。

中断处理：
- 电话/Siri/耳机拔出事件监听。
- 被中断后恢复时保持"场景参数连续"，避免突变。
- 恢复时 grain 调度器从当前 PRNG 状态继续，不需要 seek 回特定位置。

## 12. 与产品功能映射
- **轨道音量滑块** → 对应轨道 `gain` 参数平滑更新。
- **添加/移除轨道** → 动态 attach/detach SourceNode + 素材加载/释放。
- **分类切换** → 仅影响声音库 UI 展示，不触发引擎操作。
- **预设切换** → `200ms` crossfade（旧轨道淡出 + 新轨道淡入）。
- **定时结束** → 进入 `fadeOut(300s)`，完成后 stop。
- **随机音景** → 生成新 seed + 从全量声音中随机选 2~4 条轨道与参数。
- **声音预览（单击）** → 创建临时 SourceNode 播放 2 秒片段后自动释放。

## 13. 性能目标与预算
目标机型：iPhone 12 及以上（MVP）。
- 音频线程 CPU 占用：平均 < 5%，峰值 < 10%（粒子合成比纯 DSP 开销更低）。
- 内存增量：< 120MB（含缓存的素材 PCM buffer）。
- 素材包体积：内置核心 10 种 ≈ 20MB，全量 22 种 ≈ 50MB。
- 首次启动到可播放：< 1.5s（内置素材本地解码）。
- 连续后台播放 1 小时稳定无中断、无明显爆音。

## 14. 测试方案
### 14.1 粒子引擎单元测试
- grain 包络连续性测试（重叠区域无 click）。
- grain 边界安全测试（startPos + grainLen 不越界）。
- 输出 RMS 稳定性（连续 60 秒内波动 < 3dB）。
- 无 NaN/Inf 检查。
- seed 可复现验证（同 seed 两次渲染输出二进制一致）。

### 14.2 噪声 DSP 单元测试
- 白/粉/棕/蓝噪声频谱斜率验证。
- 参数边界测试（gain=0/1，极端 cutoff）。

### 14.3 集成测试
- 播放/暂停 1000 次无崩溃。
- 频繁添加/移除轨道（SourceNode attach/detach）无内存泄漏。
- 频繁切预设无 click/pop。
- 定时结束淡出曲线正确。
- 后台播放 8 小时稳定性测试。

### 14.4 听感回归
- 固定 10 组 seed 作为"黄金样本"。
- 每次版本对比 LUFS、峰值、主观听感记录。
- A/B 盲测：粒子合成 vs 循环播放（验证"永不循环"的可感知优势）。

## 15. 迭代里程碑
1. **M0（1 周）— 素材准备**
   - 采集/收集 MVP 所需的 22 种声音素材。
   - 素材剪辑、降噪、电平归一化。
   - 确认授权协议合规。

2. **M1（1 周）— 粒子引擎基础**
   - 打通 AVAudioEngine + 单轨 GrainScheduler。
   - 实现 grain 调度、Hann 窗包络、素材加载。
   - 完成播放、暂停、音量平滑。

3. **M2（1 周）— 多轨 + 噪声 + 预设**
   - 支持多轨独立 SourceNode 并行渲染。
   - 接入 DSP 噪声轨道（白/粉/棕/蓝）。
   - 完成参数化预设加载与 seed 可复现。

4. **M3（1 周）— 定时 + 后台 + 稳定性**
   - 完成定时淡出、后台播放。
   - 素材按需加载与 LRU 缓存。
   - 建立自动化测试与性能基线。

5. **M4（1 周）— 调音与发布准备**
   - 各预设 grain 参数调优（密度、pitch 范围、grain 长度）。
   - 听感验收、bugfix、发布准备。

## 16. 风险与规避
- **风险**：素材质量参差不齐。
  - 规避：建立素材验收标准（电平、底噪、频响），统一后处理流程。

- **风险**：grain 拼接处可闻的 artifact（金属感、flutter）。
  - 规避：增大 grain 长度 + 提高重叠度 + Hann 窗。极端情况可回退到更长的 grain（200~500ms）。

- **风险**：素材包体积影响安装转化。
  - 规避：内置 10 种核心素材（≈20MB），其余按需下载。

- **风险**：长时间播放音量漂移或削顶。
  - 规避：主链 limiter + 定期 RMS 校验 + 预设 loudness 归一。

- **风险**：频繁 attach/detach SourceNode 导致引擎不稳。
  - 规避：预创建 8 个 SourceNode 槽位，添加/移除轨道时复用而非重建。

## 17. MVP 最小可交付定义
满足以下即达到"粒子合成核心可上线"：
- 至少 10 种自然/城市声音的粒子合成播放，听感连续无循环感。
- 白/粉/棕三类 DSP 噪声可用。
- 支持 1~8 条轨道同时混音，各轨独立音量控制。
- 预设参数可保存/加载（含 seed 可复现）。
- 播放/暂停/定时淡出稳定，无明显爆音与断裂。
- 后台播放稳定。

## 18. 核心实现细节补充

### 18.1 Grain 对象池
- 每条轨道预分配 `maxVoices = 32` 个 GrainVoice。
- 32 个足够支持最高密度下的 grain 重叠（24 活跃 + 8 冗余）。
- 池满时跳过本次 spawn，不做动态扩容。

### 18.2 Hann 窗表
- 预计算 1024 点 Hann 窗存为 `[Float]`。
- 渲染时按 grain 进度线性插值查表，避免实时计算三角函数。

### 18.3 Pitch 偏移实现
- MVP 用线性插值变速（改变 buffer 读取步进）：
  - `readStep = 1.0 + pitch * 0.0595`（1 半音 ≈ 5.95% 速度变化）
  - 简单高效，±0.5 半音内听感自然。
- V2 可升级为相位声码器（phase vocoder）实现变调不变速。

### 18.4 默认动态处理参数（Master）
`AVAudioUnitDynamicsProcessor` 建议起始值：
- `threshold = -8 dB`
- `headRoom = 5 dB`
- `expansionRatio = 1.0`
- `attackTime = 0.001`
- `releaseTime = 0.08`
- `masterGain = 0 dB`

### 18.5 定时淡出实现
- 定时结束时不直接 `stop()`，进入淡出状态。
- `fadeGain = max(0, 1 - elapsed / fadeOutSec)`。
- 当 `fadeGain <= 0.001` 时再触发真正停播。
- 默认 `fadeOutSec = 300`（最后 5 分钟淡出）。

### 18.6 预设切换 crossfade
- 旧轨道集合执行 `200ms` fadeOut。
- fadeOut 完成后 detach 旧轨道、attach 新轨道并执行 `200ms` fadeIn。
- 如果新旧预设有共同轨道（相同 soundId），仅平滑过渡参数差异，不重建 SourceNode。

### 18.7 素材预处理脚本（建议）
```bash
# 统一转换为 48kHz 16bit mono CAF
for f in raw/*.wav; do
  afconvert "$f" -f caff -d LEI16@48000 -c 1 "assets/$(basename "$f" .wav).caf"
done

# 电平归一化到 -6dBFS
for f in assets/*.caf; do
  ffmpeg -i "$f" -af "loudnorm=I=-6:TP=-1:LRA=7" -y "$f.tmp" && mv "$f.tmp" "$f"
done
```
