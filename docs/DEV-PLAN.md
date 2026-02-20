# QuietNest 开发计划

## 目录结构规划

```
QuietNest/
├── App/
│   └── QuietNestApp.swift              # 入口
├── Views/
│   └── ContentView.swift               # UI（已完成）
├── Audio/
│   ├── AudioEngineManager.swift        # 音频引擎管理（AVAudioEngine 生命周期、轨道管理）
│   ├── GrainScheduler.swift            # 粒子调度器（render 回调核心）
│   ├── GrainVoice.swift                # grain 播放实例（struct 值类型）
│   ├── NoiseDSP.swift                  # 白/粉/棕/蓝噪声 DSP 生成
│   ├── ParamSmoother.swift             # 参数平滑器
│   └── Xoshiro256.swift                # 确定性 PRNG
├── Models/
│   ├── TrackParams.swift               # 轨道参数模型
│   └── SoundAsset.swift                # 声音素材定义与元数据
├── Services/
│   ├── AssetCache.swift                # 素材加载、解码、LRU 缓存
│   └── AtomicParamBox.swift            # 无锁参数传递
└── Resources/
    └── Assets/                         # 音频素材文件（.caf）
```

## 开发阶段

### Phase 1：音频引擎基础（核心骨架）
> 目标：能从代码层面播放出声音

1. **创建目录结构与 project.yml 更新**
   - 新增 Audio/、Models/、Services/ 源码目录
   - 更新 XcodeGen 配置

2. **实现基础工具类**
   - `Xoshiro256.swift` — 确定性 PRNG（struct 值类型）
   - `ParamSmoother.swift` — 一阶平滑器（struct 值类型）
   - `AtomicParamBox.swift` — 无锁参数传递

3. **实现 NoiseDSP**
   - 白噪声、粉噪声、棕噪声、蓝噪声的实时生成
   - 每种噪声独立 render 方法
   - 不依赖素材文件，可立即验证

4. **实现 AudioEngineManager（基础版）**
   - AVAudioEngine 初始化与信号链搭建
   - AVAudioSession 配置（.playback）
   - 支持添加/移除 DSP 噪声轨道
   - 播放/暂停控制

5. **验证**：添加一条白噪声轨道，能听到声音输出

### Phase 2：粒子合成引擎
> 目标：能用真实录音素材做粒子合成播放

6. **实现 GrainVoice**
   - struct 值类型，从素材裸指针读采样
   - Hann 窗包络、pitch 偏移、pan 处理

7. **实现 GrainScheduler**
   - grain 调度（密度控制、spawn 间隔）
   - 对象池管理（预分配 32 个 voice）
   - 用 Xoshiro256 控制随机序列

8. **实现 AssetCache**
   - 从 bundle 加载 .caf 文件解码为 PCM buffer
   - UnsafePointer 提取，提供给音频线程
   - LRU 缓存策略

9. **AudioEngineManager 扩展**
   - 支持添加粒子合成轨道（granular 类型）
   - 轨道类型分发（granular vs dsp）

10. **验证**：用一个测试素材做粒子合成，听感连续无循环

### Phase 3：UI 对接
> 目标：UI 操作能真正控制音频

11. **创建 AudioManager（桥接层）**
    - ObservableObject，供 SwiftUI 绑定
    - 封装 AudioEngineManager，提供 SwiftUI 友好的接口
    - 管理当前轨道列表与参数同步

12. **对接核心操作**
    - 播放/暂停 → engine.start/pause
    - 轨道音量滑块 → 实时参数更新
    - 添加/移除轨道 → engine.addTrack/removeTrack
    - 声音预览（单击）→ 临时播放 2 秒

13. **对接预设切换**
    - 切换预设 → crossfade 轨道替换
    - 随机音景 → 新 seed + 随机轨道组合

14. **对接定时器**
    - 定时结束 → fadeOut(300s) → stop

### Phase 4：稳定性与后台
> 目标：可以后台持续播放，应对系统中断

15. **后台播放**
    - Background Modes 配置
    - AVAudioSession 中断处理（电话、Siri、耳机拔出）
    - 恢复后参数连续

16. **稳定性优化**
    - SourceNode 槽位复用（预创建 8 个）
    - 素材按需加载的异步安全
    - 防爆音 limiter 调参

### Phase 5：调音与发布准备
> 目标：各预设听感达标

17. **各预设 grain 参数调优**
    - 密度、pitch 范围、grain 长度的最佳组合
    - 预设之间的 loudness 归一

18. **测试**
    - 播放/暂停循环稳定性
    - 轨道频繁增删无泄漏
    - 后台长时间播放

## 当前优先级
**从 Phase 1 开始，先让噪声类轨道出声音。** 粒子合成依赖素材文件，可以在 Phase 2 用测试素材或合成 buffer 代替，不阻塞引擎开发。
