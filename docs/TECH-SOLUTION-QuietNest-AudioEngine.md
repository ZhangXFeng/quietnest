# QuietNest 技术方案（程序化音频核心）v1.0

## 1. 目标与范围
本文档定义 QuietNest iOS App 的程序化音频引擎实现方案，覆盖：
- 实时音频引擎架构（AVAudioEngine）
- 噪声生成与环境事件合成算法
- 场景参数模型与随机可复现机制
- 性能、稳定性、测试与迭代计划

不包含：
- 账号体系、云同步、运营后台
- 复杂音乐生成（MIDI/和声/旋律编排）

## 2. 核心设计原则
- 实时优先：DSP 全程在音频线程执行，避免主线程参与计算。
- 稳定无缝：无循环拼接断点、无 click/pop、无爆音。
- 参数驱动：预设保存参数，不保存大体积混音音频文件。
- 可复现随机：同一 `seed + preset` 必须生成一致声景。
- 低功耗：后台运行可持续，CPU 与电量可控。

## 3. 总体架构
### 3.1 分层
1. UI 层
- 展示轨道、参数、定时器、预设。
- 不直接做 DSP，仅发送控制命令。

2. Audio Control 层
- 统一接收 UI 命令，更新引擎参数。
- 管理场景切换、淡入淡出、播放状态机。

3. DSP Engine 层（核心）
- 实时生成噪声底层（白/粉/棕/蓝）。
- 事件合成（雨滴、雷声、火苗等）。
- 混音、滤波、动态处理（limiter）。

4. Persistence 层
- 保存参数化预设、用户偏好、seed。
- 本地 JSON/SQLite（MVP 推荐 JSON + UserDefaults）。

### 3.2 iOS 组件建议
- `AVAudioEngine`
- `AVAudioSourceNode`（实时采样生成）
- `AVAudioMixerNode`（分层混音）
- `AVAudioUnitEQ`（色彩与场景滤波）
- `AVAudioUnitReverb`（轻量空间感）
- `AVAudioUnitDynamicsProcessor`（防爆音）

## 4. 音频信号链
建议节点连接顺序：

`SourceNode(noise+events)`  
-> `TrackMixer`  
-> `SceneEQ`  
-> `Reverb(send)`  
-> `MasterDynamics(limiter)`  
-> `MainMixer`  
-> `Output`

说明：
- `TrackMixer` 内部保留每轨独立增益（0~1）与静音态。
- `MasterDynamics` 必须在输出前，防止随机峰值削顶失真。

## 5. 程序化核心算法
### 5.1 基础噪声生成
统一用白噪声作为输入：

`white[n] = random(-1, 1)`

通过滤波得到不同“颜色”噪声。

1. 白噪声（White）
- 直接输出或仅做轻微高切（避免刺耳）。

2. 粉噪声（Pink）
- 采用 Paul Kellet 近似滤波（低成本，实时友好）。
- 用若干一阶滤波状态变量累加得到 `1/f` 频谱近似。

3. 棕噪声（Brown）
- 白噪声积分后泄漏修正：
- `brown[n] = (brown[n-1] + k * white[n]) * leak`
- 推荐 `leak` 在 `0.98~0.995`。

4. 蓝噪声（Blue）
- 可用高通白噪声近似：
- `blue[n] = white[n] - white[n-1]`
- 再做幅度归一与轻微平滑。

## 5.2 环境事件层（Texture Events）
目标：避免“纯噪声听久单调”，增加真实感微变化。

### 5.2.1 事件调度模型
- 每类事件使用泊松过程触发：
- `P(k events in t) = (lambda*t)^k * e^(-lambda*t) / k!`
- 实现上按每帧/每 buffer 抽样触发。

### 5.2.2 事件模板
1. 雨滴
- 短包络脉冲（2~20ms attack, 30~120ms decay）
- 随机中心频率（1k~6kHz）带通后叠加。

2. 风阵
- 低频噪声调制增益（slow LFO + random walk）
- 事件长度 2~12s，缓慢起伏。

3. 远雷
- 低频滚动噪声 + 低通 + 长衰减（2~8s）
- 稀疏触发（低 `lambda`）。

4. 火苗噼啪
- 高频短突发 + 随机脉冲序列
- 高频占比高，音量小，密度中等。

## 5.3 参数平滑与无点击控制
所有可变参数（音量、滤波 cutoff、send 量）不可瞬变，需平滑：
- 一阶平滑：
- `y[n] = y[n-1] + a * (target - y[n-1])`
- 建议平滑时间常数 `20~80ms`。

开始/停止与场景切换：
- 统一执行 `50~300ms` ramp/crossfade，避免 click/pop。

## 5.4 立体声空间处理（轻量）
- 每个事件实例给随机 `pan`（-0.4~0.4）。
- 主体底噪居中，事件轻度左右漂移。
- 避免过宽导致耳机疲劳。

## 6. 场景参数化模型
每个预设保存为参数快照（示例）：

```json
{
  "presetId": "sleep_rain_room",
  "name": "雨夜书房",
  "seed": 104729,
  "baseNoises": [
    { "type": "pink", "gain": 0.42, "lpHz": 4200 },
    { "type": "brown", "gain": 0.25, "lpHz": 1800 }
  ],
  "events": {
    "raindrop": { "enabled": true, "density": 0.65, "gain": 0.30 },
    "thunder": { "enabled": true, "density": 0.08, "gain": 0.18 },
    "fireCrackle": { "enabled": true, "density": 0.22, "gain": 0.14 }
  },
  "space": { "reverbMix": 0.12 },
  "master": { "gain": 0.85 }
}
```

参数建议范围：
- `gain`: `0.0~1.0`
- `density`: `0.0~1.0`（映射到 `lambda`）
- `lpHz`: `150~10000`
- `reverbMix`: `0.0~0.25`（助眠可略高，专注偏低）

## 7. 随机与可复现机制
- 使用固定种子 PRNG（如 Xoroshiro/PCG）。
- 每个预设保存：
- `globalSeed`：整体随机序列入口。
- `streamSeed`：按模块派生（noise/events/pan）。

派生示例：
- `noiseSeed = hash(globalSeed, "noise")`
- `eventSeed = hash(globalSeed, "event")`

这样“随机音景”可分享、可恢复、可 A/B 对比。

## 8. iOS 实现骨架（Swift）
```swift
final class AudioEngineManager {
    private let engine = AVAudioEngine()
    private let mainMixer = AVAudioMixerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private let limiter = AVAudioUnitDynamicsProcessor()
    private var sourceNode: AVAudioSourceNode!
    private let dsp = DSPCore(sampleRate: 48000)

    func setup() throws {
        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            self.dsp.render(frameCount: Int(frameCount), abl: abl)
            return noErr
        }

        engine.attach(sourceNode)
        engine.attach(eq)
        engine.attach(limiter)

        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        engine.connect(sourceNode, to: eq, format: format)
        engine.connect(eq, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)

        configureLimiter()
        try engine.start()
    }

    func update(_ params: SceneParams) {
        dsp.enqueue(params) // lock-free/single-writer message
    }
}
```

`DSPCore` 关键点：
- 在 `render()` 内仅做纯计算，不分配内存、不打日志、不锁 mutex。
- 使用预分配 buffer 与对象池保存事件实例。
- 参数更新通过无锁 ring buffer 或原子快照下发。

## 9. 线程模型与实时安全
- 主线程：UI 交互与参数编辑。
- 控制线程：参数合并、状态机处理（可与主线程合并）。
- 音频线程（实时）：仅拉取最新参数快照 + 渲染采样。

禁止在音频回调中做：
- `malloc/free`
- 文件 IO、网络 IO
- 锁等待（mutex/semaphore）
- Objective-C 动态消息风暴

## 10. 后台播放与系统会话
- `AVAudioSession` 建议：
- category: `.playback`
- mode: `.default`
- options: 依据需求决定是否 `mixWithOthers`
- 配置后台音频能力（Background Modes -> Audio）。

中断处理：
- 电话/Siri/耳机拔出事件监听。
- 被中断后恢复时保持“场景参数连续”，避免突变。

## 11. 与产品功能映射
- 轨道音量滑块 -> 对应 `baseNoises/events gain` 参数平滑更新。
- 分类切换 -> 切换可选参数模板，不强制立刻重建图。
- 预设切换 -> `200ms` crossfade 到新参数快照。
- 定时结束 -> 进入 `fadeOut(300s)`，完成后 stop。
- 随机音景 -> 生成新 seed + 参数扰动（受约束范围）。

## 12. 性能目标与预算
目标机型：iPhone 12 及以上（MVP）。
- 音频线程 CPU 占用：平均 < 8%，峰值 < 15%。
- 内存增量：< 80MB。
- 首次启动到可播放：< 1.5s（本地资源）。
- 连续后台播放 1 小时稳定无中断、无明显爆音。

## 13. 测试方案
### 13.1 DSP 单元测试
- 噪声统计特性测试（RMS、频谱斜率区间）。
- 参数边界测试（0/1、极小/极大 cutoff）。
- 无 NaN/Inf 检查。

### 13.2 集成测试
- 播放/暂停 1000 次无崩溃。
- 频繁切预设无 click/pop。
- 定时结束淡出曲线正确。

### 13.3 听感回归
- 固定 10 组 seed 作为“黄金样本”。
- 每次版本对比 LUFS、峰值、主观听感记录。

## 14. 迭代里程碑
1. M1（1 周）
- 打通 AVAudioEngine + White/Pink/Brown 基础噪声。
- 完成播放、暂停、音量平滑。

2. M2（1 周）
- 接入事件层（雨滴/风/雷/火）与参数化预设。
- 完成随机可复现（seed）机制。

3. M3（1 周）
- 完成定时淡出、后台播放、稳定性优化。
- 建立基础自动化测试与性能基线。

4. M4（1 周）
- 调音、听感验收、bugfix、发布准备。

## 15. 风险与规避
- 风险：实时算法复杂度过高导致掉帧。
- 规避：优先低阶滤波与轻量事件，不做重卷积。

- 风险：随机音景听感不稳定。
- 规避：参数扰动使用约束区间 + 风格模板。

- 风险：长时间播放音量漂移或削顶。
- 规避：主链 limiter + 定期 RMS 校验 + 预设 loudness 归一。

## 16. MVP 最小可交付定义
满足以下即达到“程序化核心可上线”：
- 支持白/粉/棕三类实时噪声。
- 至少 2 类事件层（雨滴、风）可调密度与音量。
- 预设参数可保存/加载（含 seed）。
- 播放/暂停/定时淡出稳定，无明显爆音与断裂。

## 17. 核心实现细节（可直接编码）
### 17.1 参数与数据结构（建议）
```swift
struct SceneParams: Codable {
    var seed: UInt64
    var masterGain: Float          // 0...1
    var reverbMix: Float           // 0...0.25
    var fadeOutSec: Float          // e.g. 300 for timer ending
    var base: [BaseNoiseParam]
    var events: EventGroupParam
}

struct BaseNoiseParam: Codable {
    var type: NoiseType            // white/pink/brown/blue
    var gain: Float                // 0...1
    var lowPassHz: Float           // 150...10000
}

struct EventParam: Codable {
    var enabled: Bool
    var density: Float             // 0...1
    var gain: Float                // 0...1
    var attackMs: Float
    var decayMs: Float
}

struct EventGroupParam: Codable {
    var raindrop: EventParam
    var windGust: EventParam
    var thunder: EventParam
    var fireCrackle: EventParam
}
```

### 17.2 `density -> lambda` 映射
为保证听感可控，不建议线性映射，建议平方映射让低密度更细腻：
- `lambda = minRate + (maxRate - minRate) * density^2`

推荐默认值（事件/秒）：
- `raindrop`: `min=1.0`, `max=28.0`
- `fireCrackle`: `min=0.5`, `max=18.0`
- `windGust`: `min=0.02`, `max=0.6`
- `thunder`: `min=0.003`, `max=0.08`

### 17.3 音频回调渲染伪代码
```text
for frame in bufferFrames:
  sampleL = 0
  sampleR = 0

  updateSmoothedParams()               // gain/cutoff/send ramp

  // 1) base noise layers
  for noise in baseNoises:
    n = noiseGenerator(noise.type)
    n = onePoleLPF(n, noise.lowPassHz)
    n *= noise.smoothedGain
    sampleL += n
    sampleR += n

  // 2) spawn events by Poisson process
  spawnIfNeeded(event: raindrop)
  spawnIfNeeded(event: windGust)
  spawnIfNeeded(event: thunder)
  spawnIfNeeded(event: fireCrackle)

  // 3) render active event voices
  for voice in activeVoices:
    v = voice.nextSample()             // envelope + filter + pan
    sampleL += v.left
    sampleR += v.right

  // 4) timer fade out
  fadeGain = timerFadeEnvelope()
  sampleL *= fadeGain
  sampleR *= fadeGain

  // 5) soft clip safety (pre-limiter guard)
  sampleL = tanh(sampleL * 0.9)
  sampleR = tanh(sampleR * 0.9)

  outL[frame] = sampleL
  outR[frame] = sampleR
```

### 17.4 事件对象池
- 固定池大小，避免回调内动态分配。
- 推荐 `maxVoices`：
- `raindrop=48`
- `fireCrackle=24`
- `windGust=4`
- `thunder=3`

当池满时直接丢弃低优先级新事件，保证实时性优先于完整性。

### 17.5 默认动态处理参数（Master）
`AVAudioUnitDynamicsProcessor` 建议起始值：
- `threshold = -8 dB`
- `headRoom = 5 dB`
- `expansionRatio = 1.0`
- `attackTime = 0.001`
- `releaseTime = 0.08`
- `masterGain = 0 dB`

说明：这是“保守防爆”初值，后续根据听感与 LUFS 再微调。

### 17.6 定时淡出实现
- 定时结束时不直接 `stop()`，进入淡出状态。
- `fadeGain = max(0, 1 - elapsed / fadeOutSec)`。
- 当 `fadeGain <= 0.001` 时再触发真正停播。

### 17.7 预设切换 crossfade
- 维护 `oldScene` 与 `newScene` 并行渲染 `200ms`。
- `mix = elapsed / 0.2s`
- `out = old*(1-mix) + new*mix`

这样切换预设时不会出现相位跳变与爆音。
