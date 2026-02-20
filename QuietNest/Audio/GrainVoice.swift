import Foundation

/// 单个 grain 播放实例（struct 值类型，音频线程零 ARC 开销）
struct GrainVoice {
    var isActive: Bool = false
    var startPos: Int = 0           // 素材中的起始采样点
    var grainLen: Int = 0           // grain 总长度（采样数）
    var cursor: Int = 0             // 当前播放位置
    var readStep: Float = 1.0       // 读取步进（用于 pitch 偏移）
    var pan: Float = 0              // -0.5~0.5
    var gain: Float = 1.0

    /// 激活一个 grain
    mutating func activate(
        startPos: Int,
        grainLen: Int,
        pitch: Float,
        pan: Float,
        gain: Float
    ) {
        self.isActive = true
        self.startPos = startPos
        self.grainLen = grainLen
        self.cursor = 0
        // pitch（半音）-> 速度比：2^(pitch/12) ≈ 1 + pitch * 0.0595（小范围近似）
        self.readStep = 1.0 + pitch * 0.0595
        self.pan = pan
        self.gain = gain
    }

    /// 从素材读取一个采样，施加窗口与 pan，返回立体声
    @inline(__always)
    mutating func nextSample(
        pcm: UnsafePointer<Float>,
        pcmLen: Int,
        window: UnsafePointer<Float>,
        windowSize: Int
    ) -> (Float, Float) {
        guard isActive, grainLen > 0 else { return (0, 0) }

        // Hann 窗查表（线性插值）
        let windowPos = Float(cursor) / Float(grainLen) * Float(windowSize - 1)
        let windowIdx = Int(windowPos)
        let windowFrac = windowPos - Float(windowIdx)
        let w0 = window[min(windowIdx, windowSize - 1)]
        let w1 = window[min(windowIdx + 1, windowSize - 1)]
        let envelope = w0 + windowFrac * (w1 - w0)

        // 从素材读取（线性插值变速）
        let floatPos = Float(startPos) + Float(cursor) * readStep
        let intPos = Int(floatPos)
        let frac = floatPos - Float(intPos)
        let safePos0 = ((intPos % pcmLen) + pcmLen) % pcmLen
        let safePos1 = (((intPos + 1) % pcmLen) + pcmLen) % pcmLen
        let s0 = pcm[safePos0]
        let s1 = pcm[safePos1]
        let sample = (s0 + frac * (s1 - s0)) * envelope * gain

        // equal-power pan: panR in [0, 1]
        let panR = pan + 0.5  // pan: -0.5~0.5 -> 0~1
        let left  = sample * sqrt(max(0, 1.0 - panR))
        let right = sample * sqrt(max(0, panR))

        cursor += 1
        if cursor >= grainLen {
            isActive = false
        }

        return (left, right)
    }
}
