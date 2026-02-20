import Foundation

/// 一阶参数平滑器（值类型，实时安全）
/// 用于音量、滤波等参数的无点击平滑过渡
struct ParamSmoother {
    private var current: Float
    private var target: Float
    private let coefficient: Float  // 每采样的平滑系数

    /// - Parameters:
    ///   - initial: 初始值
    ///   - smoothTimeMs: 平滑时间常数（毫秒）
    ///   - sampleRate: 采样率
    init(initial: Float, smoothTimeMs: Float = 50, sampleRate: Float = 48_000) {
        self.current = initial
        self.target = initial
        // tau = smoothTimeMs / 1000 * sampleRate
        // coefficient = 1 - exp(-1 / tau)
        let tau = smoothTimeMs / 1000.0 * sampleRate
        self.coefficient = 1.0 - exp(-1.0 / max(tau, 1.0))
    }

    /// 设置目标值（从主线程调用）
    mutating func setTarget(_ value: Float) {
        target = value
    }

    /// 推进一个采样，返回平滑后的当前值（在 render 回调中调用）
    @inline(__always)
    mutating func next() -> Float {
        current += coefficient * (target - current)
        return current
    }

    /// 立即跳到目标值（用于初始化或强制重置）
    mutating func snap() {
        current = target
    }

    /// 当前是否已收敛（差异小于阈值）
    var isSettled: Bool {
        abs(target - current) < 0.0001
    }

    var value: Float { current }
    var targetValue: Float { target }
}

/// 用于 fadeOut 的线性渐变器
struct LinearFade {
    private var current: Float = 1.0
    private var step: Float = 0
    private(set) var isActive: Bool = false

    /// 开始淡出
    /// - Parameters:
    ///   - durationSec: 淡出时长（秒）
    ///   - sampleRate: 采样率
    mutating func startFadeOut(durationSec: Float, sampleRate: Float = 48_000) {
        let totalSamples = durationSec * sampleRate
        step = -1.0 / max(totalSamples, 1.0)
        current = 1.0
        isActive = true
    }

    /// 重置（取消淡出）
    mutating func reset() {
        current = 1.0
        step = 0
        isActive = false
    }

    /// 推进一个采样，返回当前增益
    @inline(__always)
    mutating func next() -> Float {
        guard isActive else { return 1.0 }
        current += step
        if current <= 0.001 {
            current = 0
            isActive = false
        }
        return max(current, 0)
    }

    var value: Float { current }
    var isFinished: Bool { isActive == false && current <= 0.001 }
}
